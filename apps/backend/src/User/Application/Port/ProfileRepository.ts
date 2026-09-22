import type { UserProfile } from "../../Domain/Model/UserProfile";

export interface ProfileRepository {
  isAccountActive(userId: string, accessToken: string): Promise<boolean>;
  find(userId: string, accessToken: string): Promise<UserProfile | null>;
  save(profile: UserProfile, accessToken: string): Promise<UserProfile>;
}

export class AccountDeletionInProgressError extends Error {
  constructor() {
    super("Account deletion is in progress.");
    this.name = "AccountDeletionInProgressError";
  }
}
