import Link from "next/link";
const groups = [
  ["Dashboard","/dashboard"],["Signing","/signing"],["Security","/security"],["Administration","/administration"],["Audit","/audit"],["System","/system"]
];
export function AppShell({children}:{children:React.ReactNode}) { return <div className="min-h-screen md:grid md:grid-cols-[250px_1fr]">
  <aside className="border-r bg-[var(--card)] p-4"><div className="mb-8 flex items-center gap-3"><div className="grid size-9 place-items-center rounded-lg bg-[var(--primary)] font-bold text-white">SZ</div><div><div className="font-semibold">SignZone</div><div className="text-xs text-[var(--muted-foreground)]">Signing appliance</div></div></div>
  <nav className="space-y-1">{groups.map(([n,h])=><Link key={h} href={h} className="block rounded-lg px-3 py-2 text-sm hover:bg-[var(--muted)]">{n}</Link>)}</nav></aside>
  <main><header className="flex h-16 items-center justify-between border-b px-6"><div className="text-sm text-[var(--muted-foreground)]">Production zone</div><div className="text-sm">Security Admin</div></header><div className="p-6">{children}</div></main>
</div> }
