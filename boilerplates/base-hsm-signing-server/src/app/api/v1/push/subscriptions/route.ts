import { z } from "zod";
const schema=z.object({endpoint:z.string().url(),keys:z.object({p256dh:z.string().min(1),auth:z.string().min(1)})}).strict();
export async function POST(req:Request){const parsed=schema.safeParse(await req.json().catch(()=>null));if(!parsed.success)return Response.json({error:"invalid_request"},{status:400});/* SECURITY-BLOCKED: authenticate user, encrypt-at-rest endpoint/key data, rate-limit, audit. */return Response.json({error:"not_implemented_securely"},{status:501});}
