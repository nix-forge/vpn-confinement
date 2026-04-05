import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://ianhollow.github.io",
  base: "/vpn-confinement/",
  integrations: [
    starlight({
      title: "vpn-confinement",
      description:
        "Fail-closed WireGuard confinement for selected NixOS services",
      logo: {
        src: "./src/assets/logo-512.png",
        alt: "vpn-confinement",
      },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/IanHollow/vpn-confinement",
        },
      ],
      sidebar: [
        {
          label: "Guides",
          items: [
            { label: "Overview", slug: "index" },
            { label: "Architecture", slug: "architecture" },
            { label: "Threat Model", slug: "threat-model" },
            { label: "Options", slug: "options" },
            { label: "Contributing", slug: "contributing" },
            { label: "Code of Conduct", slug: "code-of-conduct" },
            { label: "Security", slug: "security" },
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
      ],
    }),
  ],
});
