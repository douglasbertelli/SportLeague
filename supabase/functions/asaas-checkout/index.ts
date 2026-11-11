// Começa a assinatura do Premium: cria (ou reaproveita) o cliente no Asaas
// e devolve o link do pagamento: no cartão, um checkout recorrente mensal;
// no Pix, a fatura da primeira cobrança de uma assinatura mensal.
//
// Chamada pelo site com o login do administrador e
// `{ "cpfCnpj": "...", "phone": "...", "method": "card" | "pix" }`.
// O Asaas exige telefone e endereço do cliente: o endereço vem do cadastro
// (tabela addresses) e o celular informado fica salvo no perfil.
// O valor sai do banco (Premium + times ativos), nunca do pedido.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin, asaas, AsaasError, caller, cors, json, todayBrt, webUrl } from "../_shared/asaas.ts";
import { checkoutImage } from "../_shared/checkout-image.ts";

function validCpf(d: string) {
  if (d.length !== 11 || /^(\d)\1+$/.test(d)) return false;
  const digit = (n: number) => {
    let sum = 0;
    for (let i = 0; i < n; i++) sum += Number(d[i]) * (n + 1 - i);
    const r = (sum * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return digit(9) === Number(d[9]) && digit(10) === Number(d[10]);
}

function validCnpj(d: string) {
  if (d.length !== 14 || /^(\d)\1+$/.test(d)) return false;
  const digit = (n: number) => {
    const weights = n === 12
      ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
      : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const sum = weights.reduce((s, w, i) => s + w * Number(d[i]), 0);
    const r = sum % 11;
    return r < 2 ? 0 : 11 - r;
  };
  return digit(12) === Number(d[12]) && digit(13) === Number(d[13]);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });

  const user = await caller(request);
  if (!user) return json({ error: "not_signed_in" }, 401);

  const body = await request.json().catch(() => ({}));
  const cpfCnpj = String(body.cpfCnpj ?? "").replace(/\D/g, "");
  if (!validCpf(cpfCnpj) && !validCnpj(cpfCnpj)) {
    return json({ error: "invalid_document" }, 400);
  }
  const phone = String(body.phone ?? "").replace(/\D/g, "");
  if (!/^\d{10,11}$/.test(phone)) return json({ error: "invalid_phone" }, 400);
  const method = body.method === "pix" ? "pix" : "card";

  const { data: profile } = await admin
    .from("profiles")
    .select("id, full_name, role, plan")
    .eq("id", user.id)
    .maybeSingle();
  if (!profile || profile.role !== "admin") return json({ error: "not_admin" }, 403);
  if (profile.plan === "elite") return json({ error: "elite" }, 409);

  const { data: address } = await admin
    .from("addresses")
    .select("zip_code, street, number, complement, neighborhood")
    .eq("profile_id", user.id)
    .maybeSingle();
  if (!address) return json({ error: "no_address" }, 409);
  await admin.from("profiles").update({ phone }).eq("id", user.id);

  const { data: current } = await admin
    .from("subscriptions")
    .select()
    .eq("profile_id", user.id)
    .maybeSingle();
  if (current && ["active", "overdue"].includes(current.status)) {
    return json({ error: "already_subscribed" }, 409);
  }

  const { data: desired } = await admin.rpc("asaas_desired_value", { uid: user.id });
  const { teams, value_cents } = desired as { teams: number; value_cents: number };

  try {
    // Cliente: um por conta. Se o documento mudou, atualiza.
    let customerId = current?.asaas_customer_id as string | undefined;
    const customer = {
      name: profile.full_name,
      cpfCnpj,
      email: user.email,
      phone,
      mobilePhone: phone.length === 11 ? phone : undefined,
      postalCode: address.zip_code,
      address: address.street,
      addressNumber: address.number,
      complement: address.complement ?? undefined,
      province: address.neighborhood,
      externalReference: user.id,
      notificationDisabled: false,
    };
    if (customerId) {
      await asaas("PUT", `/customers/${customerId}`, customer);
    } else {
      const created = await asaas<{ id: string }>("POST", "/customers", customer);
      customerId = created.id;
    }

    await admin.from("subscriptions").upsert({
      profile_id: user.id,
      asaas_customer_id: customerId,
      status: current?.status === "canceled" ? "canceled" : "pending",
      teams,
      value_cents,
      updated_at: new Date().toISOString(),
    });

    // Uma tentativa anterior que ficou sem pagar (Pix) é trocada pela nova.
    if (current?.status === "pending" && current.asaas_subscription_id) {
      await asaas("DELETE", `/subscriptions/${current.asaas_subscription_id}`).catch(
        (e) => console.warn("asaas-checkout old", e instanceof AsaasError ? e.status : e),
      );
      await admin
        .from("subscriptions")
        .update({ asaas_subscription_id: null })
        .eq("profile_id", user.id);
    }

    // Quem cancelou e ainda tem dias pagos só começa a pagar depois deles.
    const today = todayBrt();
    const nextDueDate =
      current?.paid_until && current.paid_until > today ? current.paid_until : today;
    const description = teams > 1 ? `Premium com ${teams} times` : "Premium com 1 time";

    // Pix: assinatura mensal; cada mês o Asaas gera a cobrança e manda por
    // e-mail. Leva à fatura da primeira (o checkout recorrente só aceita
    // cartão).
    if (method === "pix") {
      const sub = await asaas<{ id: string }>("POST", "/subscriptions", {
        customer: customerId,
        billingType: "PIX",
        value: value_cents / 100,
        nextDueDate,
        cycle: "MONTHLY",
        description: `SportLeague ${description}`,
        externalReference: user.id,
      });
      await admin
        .from("subscriptions")
        .update({ asaas_subscription_id: sub.id })
        .eq("profile_id", user.id);
      const payments = await asaas<{ data: { invoiceUrl: string }[] }>(
        "GET",
        `/subscriptions/${sub.id}/payments`,
      );
      return json({ url: payments.data[0]?.invoiceUrl ?? `${webUrl}/conta?assinatura=ok` });
    }

    // Cartão: checkout recorrente; o cartão fica salvo no Asaas e é cobrado
    // todo mês.
    const checkout = await asaas<{ id: string; link: string }>("POST", "/checkouts", {
      billingTypes: ["CREDIT_CARD"],
      chargeTypes: ["RECURRENT"],
      minutesToExpire: 60,
      customer: customerId,
      externalReference: user.id,
      callback: {
        successUrl: `${webUrl}/conta?assinatura=ok`,
        cancelUrl: `${webUrl}/conta/assinar`,
        expiredUrl: `${webUrl}/conta/assinar`,
      },
      items: [
        {
          name: "SportLeague Premium",
          description,
          quantity: 1,
          value: value_cents / 100,
          imageBase64: await checkoutImage(),
        },
      ],
      subscription: { cycle: "MONTHLY", nextDueDate },
    });
    return json({ url: checkout.link });
  } catch (error) {
    console.error("asaas-checkout", error instanceof AsaasError ? JSON.stringify(error.body) : error);
    return json(
      { error: "asaas", message: error instanceof Error ? error.message : String(error) },
      502,
    );
  }
});
