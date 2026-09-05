"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Activity } from "lucide-react";
import { cn } from "@/lib/utils";

const links = [
  { href: "/", label: "Live" },
  { href: "/sessions", label: "Sessions" },
];

export function SiteHeader() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-20 border-b border-white/10 bg-[#06141c]/80 backdrop-blur-xl">
      <div className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5">
          <span className="flex size-8 items-center justify-center rounded-lg bg-cyan-400 text-[#06141c]">
            <Activity className="size-4" />
          </span>
          <span className="leading-tight">
            <span className="block text-sm font-semibold tracking-tight">
              Verity Sense
            </span>
            <span className="hidden text-[11px] text-cyan-100/60 sm:block">
              Polar optical HR
            </span>
          </span>
        </Link>
        <nav className="flex items-center gap-1 rounded-full bg-white/5 p-1">
          {links.map((link) => {
            const active =
              link.href === "/"
                ? pathname === "/"
                : pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={cn(
                  "rounded-full px-3 py-1 text-sm transition-colors",
                  active
                    ? "bg-white/10 text-white"
                    : "text-white/55 hover:text-white",
                )}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
