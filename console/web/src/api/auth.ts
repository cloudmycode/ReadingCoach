import { apiRequest, clearToken, setToken } from "./client";
import type { LoginData, SendCodeData, UserInfo } from "../types/api";

export async function sendCode(phone: string): Promise<SendCodeData> {
  return apiRequest<SendCodeData>("/api/auth/code", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
}

export async function login(
  phone: string,
  code: string,
): Promise<LoginData> {
  const data = await apiRequest<LoginData>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({
      phone,
      code,
      agreePolicy: true,
    }),
  });
  setToken(data.token);
  return data;
}

export async function fetchCurrentUser(): Promise<UserInfo> {
  return apiRequest<UserInfo>("/api/auth/user");
}

export async function logout(): Promise<void> {
  try {
    await apiRequest<null>("/api/auth/logout", { method: "POST" });
  } finally {
    clearToken();
  }
}
