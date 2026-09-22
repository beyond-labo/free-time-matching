import type { ProfileRepository } from "../../Application/Port/ProfileRepository";
import type { PresetIconKey, UserProfile } from "../../Domain/Model/UserProfile";
import {
  supabaseFetch,
  type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";

interface ProfileRow {
  user_id: string;
  nickname: string;
  preset_icon_key: PresetIconKey;
}

const mapRow = (row: ProfileRow): UserProfile => ({
  userId: row.user_id,
  nickname: row.nickname,
  presetIconKey: row.preset_icon_key,
});

export class SupabaseProfileRepository implements ProfileRepository {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async isAccountActive(userId: string, accessToken: string): Promise<boolean> {
    const response = await supabaseFetch(
      this.configuration,
      "/rest/v1/rpc/is_account_active",
      { method: "POST", body: JSON.stringify({}) },
      accessToken,
    );
    const active = (await response.json()) as unknown;
    if (typeof active !== "boolean") {
      throw new Error(`Supabase returned an invalid account state for ${userId}.`);
    }
    return active;
  }

  async find(userId: string, accessToken: string): Promise<UserProfile | null> {
    const response = await supabaseFetch(
      this.configuration,
      `/rest/v1/user_profiles?select=user_id,nickname,preset_icon_key&user_id=eq.${encodeURIComponent(userId)}&limit=1`,
      { method: "GET" },
      accessToken,
    );
    const rows = (await response.json()) as ProfileRow[];
    return rows[0] ? mapRow(rows[0]) : null;
  }

  async save(profile: UserProfile, accessToken: string): Promise<UserProfile> {
    const response = await supabaseFetch(
      this.configuration,
      "/rest/v1/user_profiles?on_conflict=user_id&select=user_id,nickname,preset_icon_key",
      {
        method: "POST",
        headers: { prefer: "resolution=merge-duplicates,return=representation" },
        body: JSON.stringify({
          user_id: profile.userId,
          nickname: profile.nickname,
          preset_icon_key: profile.presetIconKey,
        }),
      },
      accessToken,
    );
    const rows = (await response.json()) as ProfileRow[];
    if (!rows[0]) throw new Error("Supabase did not return the saved profile.");
    return mapRow(rows[0]);
  }
}
