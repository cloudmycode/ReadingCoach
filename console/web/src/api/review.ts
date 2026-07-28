import { apiRequest } from "./client";
import type { WordReviewSummary, WordReviewTasksData } from "../types/api";

export async function getReviewSummary(): Promise<WordReviewSummary> {
  return apiRequest<WordReviewSummary>("/api/review/today");
}

export async function listReviewTasks(
  status: "pending" | "completed",
): Promise<WordReviewTasksData> {
  return apiRequest<WordReviewTasksData>(`/api/review/tasks?status=${status}`);
}
