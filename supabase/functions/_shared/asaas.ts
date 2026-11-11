// Chamadas à API do Asaas (v3) usadas pelas Edge Functions de assinatura.
//
// Segredos (Edge Functions → Secrets):
//   ASAAS_API_KEY: chave da API ($aact_hmlg_… no Sandbox, $aact_prod_… em
//     produção). O ambiente sai do prefixo da chave.
//   ASAAS_WEBHOOK_TOKEN: o mesmo token cadastrado no webhook do Asaas.
//   WEB_URL (opcional): endereço do site, para a volta do checkout.

import { createClient } from "npm:@supabase/supabase-js@2";

export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

export const webUrl =
  Deno.env.get("WEB_URL")?.replace(/\/$/, "") ?? "https://app.sportleague.com.br";

function apiKey() {
  const key = Deno.env.get("ASAAS_API_KEY");
  if (!key) throw new Error("ASAAS_API_KEY não configurada");
  return key;
}

const baseUrl = () =>
  apiKey().startsWith("$aact_prod_")
    ? "https://api.asaas.com/v3"
    : "https://api-sandbox.asaas.com/v3";

export class AsaasError extends Error {
  constructor(
    readonly status: number,
    readonly body: unknown,
  ) {
    const errors = (body as { errors?: { description?: string }[] })?.errors;
    super(errors?.map((e) => e.description).join("; ") || `Asaas ${status}`);
  }
}

export async function asaas<T = Record<string, unknown>>(
  method: "GET" | "POST" | "PUT" | "DELETE",
  path: string,
  body?: unknown,
): Promise<T> {
  const response = await fetch(`${baseUrl()}${path}`, {
    method,
    headers: {
      access_token: apiKey(),
      "Content-Type": "application/json",
      "User-Agent": "SportLeague/1.0",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new AsaasError(response.status, data);
  return data as T;
}

/** Hoje em Brasília (AAAA-MM-DD). */
export const todayBrt = () =>
  new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(
    new Date(),
  );

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: cors });

/** Quem chamou (pelo token do Supabase no cabeçalho Authorization). */
export async function caller(request: Request) {
  const token = request.headers.get("Authorization")?.replace(/^Bearer /, "");
  if (!token) return null;
  const { data } = await admin.auth.getUser(token);
  return data.user ?? null;
}
