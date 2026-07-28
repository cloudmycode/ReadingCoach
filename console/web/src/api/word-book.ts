import { apiRequest } from "./client";
import type { WordBookListData } from "../types/api";

export async function listWordBook(): Promise<WordBookListData> {
  return apiRequest<WordBookListData>("/api/word-book");
}

export async function deleteWordBookEntry(entryId: number): Promise<void> {
  await apiRequest<Record<string, never>>(`/api/word-book/${entryId}`, {
    method: "DELETE",
  });
}
