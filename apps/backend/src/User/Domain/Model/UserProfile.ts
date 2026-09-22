const allowedPresetIconKeys = [
  "sun.max.fill",
  "leaf.fill",
  "gamecontroller.fill",
  "figure.run",
] as const;

export type PresetIconKey = (typeof allowedPresetIconKeys)[number];

export interface UserProfile {
  readonly userId: string;
  readonly nickname: string;
  readonly presetIconKey: PresetIconKey;
}

export interface ProfileInput {
  readonly nickname: string;
  readonly presetIconKey: string;
}

export class InvalidProfileError extends Error {
  constructor(readonly fields: Readonly<Record<string, string>>) {
    super("The profile is invalid.");
    this.name = "InvalidProfileError";
  }
}

const graphemeCount = (value: string): number =>
  Array.from(
    new Intl.Segmenter("ja", { granularity: "grapheme" }).segment(value),
  ).length;

export const validateProfile = (input: ProfileInput): Omit<UserProfile, "userId"> => {
  const nickname = input.nickname.trim();
  const fields: Record<string, string> = {};
  const length = graphemeCount(nickname);
  if (length < 1 || length > 20) {
    fields.nickname = "ニックネームは1〜20文字で入力してください。";
  }
  if (!allowedPresetIconKeys.includes(input.presetIconKey as PresetIconKey)) {
    fields.presetIconKey = "定義済みのアイコンを選択してください。";
  }
  if (Object.keys(fields).length > 0) throw new InvalidProfileError(fields);

  return { nickname, presetIconKey: input.presetIconKey as PresetIconKey };
};
