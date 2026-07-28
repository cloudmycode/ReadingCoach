export interface ApiResponse<T> {
  success: boolean;
  message: string;
  data: T;
}

export interface UserInfo {
  id: number;
  nickname: string;
  avatar: string;
}

export interface LoginData {
  token: string;
  userInfo: UserInfo;
}

export interface SendCodeData {
  expiresIn: number;
  debugCode?: string;
}

export interface ArticleListItem {
  id: string;
  article_id: number;
  title: string;
  sentence_count: number;
  read_count: number;
  created_at: string;
  last_read_at?: string;
}

export interface ArticleListData {
  items: ArticleListItem[];
  limit: number;
  offset: number;
}

export interface ArticleSentence {
  id?: number;
  sentence_id: number;
  original: string;
  translation: string;
  is_favorite?: boolean;
}

export interface ArticleDetail {
  article_id: number;
  title: string;
  sentence_count: number;
  sentences: ArticleSentence[];
}

export interface ProcessArticleData {
  resource_id: string;
}

export interface UpdateTitleData {
  title: string;
}

export interface WordReviewSummary {
  due_count: number;
  completed_count: number;
  daily_limit: number;
  streak_days: number;
}

export interface WordReviewTaskItem {
  entry_id: number;
  word: string;
  normalized_word: string;
  part_of_speech: string;
  meaning: string;
  tip: string;
  sentence_original: string;
  sentence_translation: string;
  article_id: string;
  article_title: string;
  sentence_id: number;
  review_step: number;
  mastery_status: string;
  next_review_at?: string;
  last_reviewed_at?: string;
}

export interface WordReviewTasksData {
  items: WordReviewTaskItem[];
  status: "pending" | "completed";
}

export interface WordBookItem {
  entry_id: number;
  article_id: string;
  sentence_id: number;
  word: string;
  normalized_word: string;
  sentence_original: string;
  sentence_translation: string;
  part_of_speech: string;
  meaning: string;
  tip: string;
  review_step?: number;
  next_review_at?: string;
  mastery_status?: string;
  last_reviewed_at?: string;
  looked_up_at: string;
}

export interface WordBookListData {
  items: WordBookItem[];
}
