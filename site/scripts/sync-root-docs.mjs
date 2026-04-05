import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

const mappings = [
  {
    from: "CONTRIBUTING.md",
    to: "site/src/content/docs/contributing.md",
    frontmatter: {
      title: "Contributing",
      description: "How to contribute to vpn-confinement",
    },
  },
  {
    from: "CODE_OF_CONDUCT.md",
    to: "site/src/content/docs/code-of-conduct.md",
    frontmatter: {
      title: "Code of Conduct",
      description: "Community behavior standards",
    },
  },
  {
    from: "SECURITY.md",
    to: "site/src/content/docs/security.md",
    frontmatter: {
      title: "Security",
      description: "Supported versions and vulnerability reporting",
    },
  },
];

function withFrontmatter(content, frontmatter) {
  const header = [
    "---",
    `title: ${frontmatter.title}`,
    `description: ${frontmatter.description}`,
    "---",
    "",
  ].join("\n");

  return `${header}${content}`;
}

function rewriteDocContent(content) {
  return content;
}

for (const mapping of mappings) {
  const sourcePath = join(repoRoot, mapping.from);
  const targetPath = join(repoRoot, mapping.to);

  mkdirSync(dirname(targetPath), { recursive: true });

  if (!existsSync(sourcePath)) {
    throw new Error(`Missing source doc: ${mapping.from}`);
  }

  const source = readFileSync(sourcePath, "utf8");
  const normalized = rewriteDocContent(source.replace(/^#\s+.*\n/, ""));
  writeFileSync(
    targetPath,
    withFrontmatter(normalized, mapping.frontmatter),
    "utf8",
  );
}

mkdirSync(join(siteRoot, "src/assets"), { recursive: true });
cpSync(
  join(repoRoot, ".github/assets/logo-512.png"),
  join(siteRoot, "src/assets/logo-512.png"),
  {
    force: true,
  },
);

const optionsDocPath = join(
  siteRoot,
  "src/content/docs/reference/options-generated.md",
);
if (!existsSync(optionsDocPath)) {
  throw new Error(
    "Missing generated options reference: site/src/content/docs/reference/options-generated.md",
  );
}
