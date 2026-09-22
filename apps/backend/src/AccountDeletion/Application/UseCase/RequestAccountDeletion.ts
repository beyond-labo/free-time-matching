import type {
  AccountDeletionAdminPort,
  AppleAuthorizationGateway,
  CurrentIdentityGateway,
  StatusTokenIssuer,
} from "../Port/AccountDeletionPorts";
import { AppleReauthenticationError } from "../Port/AccountDeletionPorts";
import type { AccountDeletionReceipt } from "../../Domain/Model/AccountDeletion";

const actionRequiredMessage =
  "アカウントへのアクセスは停止しました。削除処理を再試行するため、しばらくしてから状況を確認してください。";

export class RequestAccountDeletion {
  constructor(
    private readonly admin: AccountDeletionAdminPort,
    private readonly apple: AppleAuthorizationGateway,
    private readonly identity: CurrentIdentityGateway,
    private readonly statusTokens: StatusTokenIssuer,
  ) {}

  async execute(input: {
    userId: string;
    accessToken: string;
    idempotencyKey: string;
    appleAuthorizationCode: string;
  }): Promise<AccountDeletionReceipt> {
    const existing = await this.admin.findByIdempotencyKey(
      input.userId,
      input.idempotencyKey,
    );
    if (existing) return this.toReceipt(existing);

    const [currentAppleSubject, appleAuthorization] = await Promise.all([
      this.identity.appleSubject(input.accessToken),
      this.apple.exchange(input.appleAuthorizationCode),
    ]);
    if (currentAppleSubject !== appleAuthorization.subject) {
      throw new AppleReauthenticationError();
    }

    const reference = createReference();
    const statusToken = await this.statusTokens.issue(reference);
    const record = await this.admin.createAccepted({
      userId: input.userId,
      idempotencyKey: input.idempotencyKey,
      reference,
      statusTokenHash: await this.statusTokens.hash(statusToken),
    });
    if (record.reference !== reference) {
      return this.toReceipt(record);
    }

    try {
      await this.admin.setStatus(record.id, "processing");
      await this.apple.revoke(appleAuthorization);
      await this.admin.deleteAuthUser(input.userId);
      const completed = await this.admin.setStatus(record.id, "completed");
      return { ...(await this.toReceipt(completed)), statusToken };
    } catch {
      try {
        const failed = await this.admin.setStatus(
          record.id,
          "actionRequired",
          actionRequiredMessage,
        );
        return { ...(await this.toReceipt(failed)), statusToken };
      } catch {
        throw new Error("Account deletion failed before its status could be persisted.");
      }
    }
  }

  private async toReceipt(record: {
    reference: string;
    status: "accepted" | "processing" | "completed" | "actionRequired";
    message?: string;
  }): Promise<AccountDeletionReceipt> {
    return {
      reference: record.reference,
      status: record.status,
      statusToken: await this.statusTokens.issue(record.reference),
      ...(record.message ? { message: record.message } : {}),
    };
  }
}

const createReference = (): string =>
  `DEL-${crypto.randomUUID().replaceAll("-", "").slice(0, 16).toUpperCase()}`;
