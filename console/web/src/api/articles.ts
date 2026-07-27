import { apiRequest } from "./client";
import type {
  ArticleDetail,
  ArticleListData,
  ArticleSentence,
  ProcessArticleData,
  UpdateTitleData,
} from "../types/api";

export async function listArticles(
  limit = 50,
  offset = 0,
): Promise<ArticleListData> {
  const query = new URLSearchParams({
    limit: String(limit),
    offset: String(offset),
  });
  return apiRequest<ArticleListData>(`/api/articles?${query.toString()}`);
}

export async function getArticleDetail(id: string): Promise<ArticleDetail> {
  return apiRequest<ArticleDetail>(`/api/articles/${encodeURIComponent(id)}`);
}

export async function processArticleText(text: string): Promise<ProcessArticleData> {
  return apiRequest<ProcessArticleData>("/api/articles/process-text", {
    method: "POST",
    body: JSON.stringify({ text }),
    timeoutMs: 120000,
  });
}

export async function updateArticleTitle(
  id: string,
  title: string,
): Promise<UpdateTitleData> {
  return apiRequest<UpdateTitleData>(
    `/api/articles/${encodeURIComponent(id)}/title`,
    {
      method: "POST",
      body: JSON.stringify({ title }),
    },
  );
}

export async function deleteArticle(id: string): Promise<void> {
  await apiRequest<Record<string, never>>(
    `/api/articles/${encodeURIComponent(id)}`,
    { method: "DELETE" },
  );
}

export async function updateSentence(
  articleId: string,
  sentenceId: number,
  original: string,
): Promise<ArticleSentence> {
  return apiRequest<ArticleSentence>(
    `/api/articles/${encodeURIComponent(articleId)}/sentences/${sentenceId}`,
    {
      method: "POST",
      body: JSON.stringify({ original }),
      timeoutMs: 90000,
    },
  );
}
