"use server";

import { Container } from "@/components/Container";
import { DynamicBreadcrumbs } from "@/components/DynamicBreadcrumbs";
import { FadeInWrapper } from "@/components/FadeInWrapper";
import { SuspenseLoading } from "@/components/SuspenseLoading";
import { Separator } from "@/components/ui/separator";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { Skeleton } from "@/components/ui/skeleton";
import { getServers } from "@/lib/db";
import { Calendar, Home, Settings, Users } from "lucide-react";
import { redirect } from "next/navigation";
import { PropsWithChildren, Suspense } from "react";

type Props = PropsWithChildren;

const items = [
  {
    title: "Dashboard",
    url: "/dashboard",
    icon: Home,
  },
  {
    title: "History",
    url: "/history",
    icon: Calendar,
  },
  {
    title: "Users",
    url: "/users",
    icon: Users,
  },
  {
    title: "Settings",
    url: "/settings",
    icon: Settings,
  },
];

export default async function layout({ children }: Props) {
  const servers = await getServers();

  if (!servers?.[0]?.api_key) {
    redirect("/setup");
  }

  return (
    <SidebarProvider>
      <>
        <Sidebar>
          <SidebarContent>
            <SidebarGroup>
              <SidebarGroupLabel>Streamystat</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  {items.map((item) => (
                    <SidebarMenuItem key={item.title}>
                      <SidebarMenuButton asChild>
                        <a href={item.url}>
                          <item.icon />
                          <span>{item.title}</span>
                        </a>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  ))}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          </SidebarContent>
        </Sidebar>
        <Suspense fallback={<SuspenseLoading />}>
          <main className="flex flex-col w-full">
            <div className="flex flex-row items-center p-4 gap-2">
              <SidebarTrigger />
              <Separator orientation="vertical" />
              <DynamicBreadcrumbs />
            </div>
            <FadeInWrapper>{children}</FadeInWrapper>
          </main>
        </Suspense>
      </>
    </SidebarProvider>
  );
}
