import type { Metadata, Viewport } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "SignZone", description: "Secure code-signing appliance", manifest: "/manifest.webmanifest" };
export const viewport: Viewport = { themeColor: "#b91c1c" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
