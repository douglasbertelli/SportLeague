// Imagem do item no checkout do Asaas: o ícone do site, em base64.
// Lida do site uma vez por instância da função.

import { encodeBase64 } from "jsr:@std/encoding@1/base64";

import { webUrl } from "./asaas.ts";

let cached: string | null = null;

export async function checkoutImage() {
  if (cached) return cached;
  const response = await fetch(`${webUrl}/icon.png`);
  if (!response.ok) throw new Error(`icon.png ${response.status}`);
  cached = encodeBase64(new Uint8Array(await response.arrayBuffer()));
  return cached;
}
