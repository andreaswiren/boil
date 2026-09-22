import { cn } from "@/lib/utils";
export function Card({className,...props}: React.HTMLAttributes<HTMLDivElement>) { return <div className={cn("rounded-xl border bg-[var(--card)] p-5 shadow-sm",className)} {...props}/>; }
