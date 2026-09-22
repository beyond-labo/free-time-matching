import type {
  AccountDeletionAdminPort,
  AccountDeletionStatusPort,
} from "../../Application/Port/AccountDeletionPorts";
import type {
  AccountDeletionRecord,
  AccountDeletionStatus,
  AccountDeletionStatusView,
} from "../../Domain/Model/AccountDeletion";
import {
  SupabaseRequestError,
  supabaseFetch,
  type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";

type DatabaseDeletionStatus = "accepted" | "processing" | "completed" | "action_required";

interface DeletionRow {
  id: string;
  user_id: string;
  idempotency_key: string;
  reference: string;
  status: DatabaseDeletionStatus;
  message: string | null;
}

const toDatabaseStatus = (status: AccountDeletionStatus): DatabaseDeletionStatus =>
  status === "actionRequired" ? "action_required" : status;

const fromDatabaseStatus = (status: DatabaseDeletionStatus): AccountDeletionStatus =>
  status === "action_required" ? "actionRequired" : status;

const mapRow = (row: DeletionRow): AccountDeletionRecord => ({
  id: row.id,
  userId: row.user_id,
  idempotencyKey: row.idempotency_key,
  reference: row.reference,
  status: fromDatabaseStatus(row.status),
  ...(row.message ? { message: row.message } : {}),
});

export class SupabaseDeletionAdminAdapter implements AccountDeletionAdminPort {
  private readonly configuration: SupabaseRestConfiguration;

  constructor(url: string, secretKey: string) {
    this.configuration = { url, apiKey: secretKey };
  }

  async findByIdempotencyKey(
    userId: string,
    idempotencyKey: string,
  ): Promise<AccountDeletionRecord | null> {
    const response = await supabaseFetch(
      this.configuration,
      `/rest/v1/account_deletion_requests?select=id,user_id,idempotency_key,reference,status,message&user_id=eq.${encodeURIComponent(userId)}&idempotency_key=eq.${encodeURIComponent(idempotencyKey)}&limit=1`,
      { method: "GET" },
    );
    const rows = (await response.json()) as DeletionRow[];
    return rows[0] ? mapRow(rows[0]) : null;
  }

  async createAccepted(input: {
    userId: string;
    idempotencyKey: string;
    reference: string;
    statusTokenHash: string;
  }): Promise<AccountDeletionRecord> {
    try {
      const response = await supabaseFetch(
        this.configuration,
        "/rest/v1/account_deletion_requests?select=id,user_id,idempotency_key,reference,status,message",
        {
          method: "POST",
          headers: { prefer: "return=representation" },
          body: JSON.stringify({
            user_id: input.userId,
            idempotency_key: input.idempotencyKey,
            reference: input.reference,
            status: "accepted",
            status_token_hash: input.statusTokenHash,
          }),
        },
      );
      const rows = (await response.json()) as DeletionRow[];
      if (!rows[0]) throw new Error("Supabase did not return the deletion request.");
      return mapRow(rows[0]);
    } catch (error) {
      if (error instanceof SupabaseRequestError && error.status === 409) {
        const existing = await this.findByIdempotencyKey(
          input.userId,
          input.idempotencyKey,
        );
        if (existing) return existing;
      }
      throw error;
    }
  }

  async setStatus(
    id: string,
    status: AccountDeletionStatus,
    message?: string,
  ): Promise<AccountDeletionRecord> {
    const response = await supabaseFetch(
      this.configuration,
      `/rest/v1/account_deletion_requests?id=eq.${encodeURIComponent(id)}&select=id,user_id,idempotency_key,reference,status,message`,
      {
        method: "PATCH",
        headers: { prefer: "return=representation" },
        body: JSON.stringify({
          status: toDatabaseStatus(status),
          message: message ?? null,
          ...(status === "completed" ? { completed_at: new Date().toISOString() } : {}),
        }),
      },
    );
    const rows = (await response.json()) as DeletionRow[];
    if (!rows[0]) throw new Error("The deletion request no longer exists.");
    return mapRow(rows[0]);
  }

  async deleteAuthUser(userId: string): Promise<void> {
    await supabaseFetch(
      this.configuration,
      `/auth/v1/admin/users/${encodeURIComponent(userId)}`,
      { method: "DELETE" },
    );
  }
}

export class SupabaseDeletionStatusAdapter implements AccountDeletionStatusPort {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async get(
    reference: string,
    statusToken: string,
  ): Promise<AccountDeletionStatusView | null> {
    const response = await supabaseFetch(
      this.configuration,
      "/rest/v1/rpc/get_account_deletion_status",
      {
        method: "POST",
        body: JSON.stringify({
          p_reference: reference,
          p_status_token: statusToken,
        }),
      },
    );
    const rows = (await response.json()) as Array<{
      reference: string;
      status: DatabaseDeletionStatus;
      message: string | null;
    }>;
    const row = rows[0];
    if (!row) return null;
    return {
      reference: row.reference,
      status: fromDatabaseStatus(row.status),
      ...(row.message ? { message: row.message } : {}),
    };
  }
}
