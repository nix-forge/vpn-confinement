import starlight from "@astrojs/starlight";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://ianhollow.github.io",
  base: "/vpn-confinement/",
  integrations: [
    starlight({
      title: "vpn-confinement",
      description:
        "Fail-closed WireGuard confinement for selected NixOS services",
      logo: {
        src: "./src/assets/logo.png",
        alt: "vpn-confinement",
      },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/IanHollow/vpn-confinement",
        },
      ],
      customCss: ["./src/styles/global.css"],
      disable404Route: true,
      sidebar: [
        {
          label: "Getting Started",
          items: [{ label: "Overview", slug: "index" }],
        },
        {
          label: "Core Concepts",
          items: [
            { label: "Architecture", slug: "architecture" },
            { label: "Threat Model", slug: "threat-model" },
          ],
        },
        {
          label: "Reference",
          items: [
            {
              label: "Generated Options",
              slug: "reference/options-generated",
            },
          ],
        },
        {
          label: "Project",
          items: [
            { label: "Contributing", slug: "contributing" },
            { label: "Security", slug: "security" },
            { label: "Code of Conduct", slug: "code-of-conduct" },
          ],
        },
      ],
    }),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
