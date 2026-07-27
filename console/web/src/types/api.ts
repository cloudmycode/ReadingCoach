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
