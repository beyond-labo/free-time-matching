import type { ProfileRepository } from "../Port/ProfileRepository";
import { AccountDeletionInProgressError } from "../Port/ProfileRepository";
import {
  validateProfile,
  type ProfileInput,
  type UserProfile,
} from "../../Domain/Model/UserProfile";

export class ManageProfile {
  constructor(private readonly repository: ProfileRepository) {}

  async get(userId: string, accessToken: string): Promise<UserProfile | null> {
    await this.assertActive(userId, accessToken);
    return this.repository.find(userId, accessToken);
  }

  async put(
    userId: string,
    accessToken: string,
    input: ProfileInput,
  ): Promise<UserProfile> {
    await this.assertActive(userId, accessToken);
    return this.repository.save(
      { userId, ...validateProfile(input) },
      accessToken,
    );
  }

  private async assertActive(userId: string, accessToken: string): Promise<void> {
    if (!(await this.repository.isAccountActive(userId, accessToken))) {
      throw new AccountDeletionInProgressError();
    }
  }
}
