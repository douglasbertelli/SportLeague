// Envia o push de uma notificação para os aparelhos do destinatário, pelo
// Firebase Cloud Messaging (API HTTP v1).
//
// Chamada pelo gatilho `notifications_send_push` com `{ "id": <notificação> }`.
// Não exige login: só envia notificação criada há pouco e ainda sem push
// (`pushed_at` vazio), e marca o envio antes, então chamar de novo não repete.
//
// Segredo necessário (Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT: o JSON da conta de serviço do Firebase.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

/** Só notificações criadas nos últimos minutos recebem push. */
const MAX_AGE_MS = 10 * 60 * 1000;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

let cachedAccount: ServiceAccount | null = null;
let cachedJwt: JWT | null = null;

function firebase(): { account: ServiceAccount; jwt: JWT } {
  if (!cachedAccount || !cachedJwt) {
    const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT não configurado");
    cachedAccount = JSON.parse(raw) as ServiceAccount;
    cachedJwt = new JWT({
      email: cachedAccount.client_email,
      key: cachedAccount.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
  }
  return { account: cachedAccount, jwt: cachedJwt };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let id: unknown;
  try {
    ({ id } = await req.json());
  } catch {
    return json({ error: "body" }, 400);
  }
  if (typeof id !== "string") return json({ error: "id" }, 400);

  // Marca o envio antes de enviar: só uma chamada passa daqui.
  const since = new Date(Date.now() - MAX_AGE_MS).toISOString();
  const { data: notification, error } = await supabase
    .from("notifications")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", id)
    .is("pushed_at", null)
    .gte("created_at", since)
    .select("id, recipient_id, kind, title, body, team_id, game_id, fundraiser_id")
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!notification) return json({ sent: 0, skipped: true });

  const { data: devices, error: devicesError } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", notification.recipient_id);
  if (devicesError) return json({ error: devicesError.message }, 500);
  if (!devices?.length) return json({ sent: 0 });

  const { account, jwt } = firebase();
  const { token: accessToken } = await jwt.getAccessToken();
  const url =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  // Dados extras para o app abrir a tela certa ao tocar (todos texto).
  const data: Record<string, string> = {
    notification_id: notification.id,
    kind: notification.kind,
  };
  for (const key of ["team_id", "game_id", "fundraiser_id"] as const) {
    if (notification[key]) data[key] = notification[key];
  }

  let sent = 0;
  const stale: string[] = [];
  for (const { token } of devices) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: notification.title, body: notification.body },
          data,
          android: { priority: "high", notification: { sound: "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (response.ok) {
      sent++;
      continue;
    }
    const failure = await response.json().catch(() => null);
    const code = failure?.error?.details?.find(
      (detail: { errorCode?: string }) => detail.errorCode,
    )?.errorCode;
    // O app foi desinstalado ou o token expirou: esquece o aparelho.
    if (response.status === 404 || code === "UNREGISTERED") stale.push(token);
    else console.error("FCM", response.status, JSON.stringify(failure));
  }

  if (stale.length) {
    await supabase.from("device_tokens").delete().in("token", stale);
  }
  return json({ sent, removed: stale.length });
});
