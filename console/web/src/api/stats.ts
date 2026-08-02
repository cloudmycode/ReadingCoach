import { apiRequest } from "./client";
import type { StudyStatsOverview } from "../types/api";

export async function getStudyStatsOverview(
  days = 14,
): Promise<StudyStatsOverview> {
  return apiRequest<StudyStatsOverview>(`/api/stats/overview?days=${days}`);
}
