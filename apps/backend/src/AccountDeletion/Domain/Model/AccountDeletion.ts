export type AccountDeletionStatus = "accepted" | "processing" | "completed" | "actionRequired";

export interface AccountDeletionRecord {
  readonly id: string;
  readonly userId: string;
  readonly idempotencyKey: string;
  readonly reference: string;
  readonly status: AccountDeletionStatus;
  readonly message?: string;
}

export interface AccountDeletionReceipt {
  readonly reference: string;
  readonly status: AccountDeletionStatus;
  readonly statusToken: string;
  readonly message?: string;
}

export interface AccountDeletionStatusView {
  readonly reference: string;
  readonly status: AccountDeletionStatus;
  readonly message?: string;
}
