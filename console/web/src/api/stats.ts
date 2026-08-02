import { apiRequest } from "./client";
import type { StudyStatsOverview } from "../types/api";

export async function getStudyStatsOverview(
  days = 14,
): Promise<StudyStatsOverview> {
  return apiRequest<StudyStatsOverview>(`/api/stats/overview?days=${days}`);
}

export async function reportReviewDuration(
  seconds: number,
): Promise<{ review_seconds: number }> {
  return apiRequest<{ review_seconds: number }>("/api/stats/review-duration", {
    method: "POST",
    body: JSON.stringify({ seconds }),
  });
}

export function formatDurationMinutes(seconds = 0): string {
  if (seconds <= 0) return "0分钟";
  if (seconds < 60) return "<1分钟";
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const remain = minutes % 60;
  if (hours > 0) {
    return remain > 0 ? `${hours}小时${remain}分` : `${hours}小时`;
  }
  return `${minutes}分钟`;
}
