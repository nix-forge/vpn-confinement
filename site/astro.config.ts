import starlight from "@astrojs/starlight";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://nix-forge.github.io",
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
      favicon: "/logo-512.png",
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/nix-forge/vpn-confinement",
        },
      ],
      customCss: ["./src/styles/global.css"],
      disable404Route: true,
      sidebar: [
        {
          label: "Getting Started",
          items: [
            { label: "Overview", slug: "index" },
            { label: "Transmission setup", slug: "guides/transmission" },
            { label: "Diagnostics", slug: "guides/diagnostics" },
            { label: "Common Deployments", slug: "guides/common-deployments" },
            { label: "Reverse Proxy", slug: "guides/reverse-proxy" },
            {
              label: "Security Profile Matrix",
              slug: "guides/security-profile-decision-matrix",
            },
          ],
        },
        {
          label: "Core Concepts",
          items: [
            { label: "Architecture", slug: "architecture" },
            { label: "Threat Model", slug: "threat-model" },
          ],
        },
        {
          label: "Advanced",
          items: [
            { label: "Advanced Tuning", slug: "guides/advanced-tuning" },
            { label: "Performance", slug: "guides/performance" },
            {
              label: "Security Exceptions",
              slug: "guides/security-exceptions",
            },
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
