import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("小板凳运营后台设计变量", () => {
  it("沿用胡桃木、深青绿、象牙色与暖金的牌桌色板", () => {
    const css = readFileSync(resolve("src/styles/tokens.css"), "utf8");
    expect(css).toContain("--xbd-sidebar-bg: #201710");
    expect(css).toContain("--xbd-page-bg: #131B16");
    expect(css).toContain("--xbd-text-primary: #FFF2DD");
    expect(css).toContain("--xbd-brand-primary: #DDA950");
  });

  it("正文、次要文字和状态色在常见深色背景上至少达到 4.5:1", () => {
    const css = readFileSync(resolve("src/styles/tokens.css"), "utf8");
    const luminance = (token: string) => {
      const color = css.match(new RegExp(`--xbd-${token}: #([a-f0-9]{6})\\b`, "i"))![1];
      const rgb = [0, 2, 4].map((index) => Number.parseInt(color.slice(index, index + 2), 16) / 255)
        .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
      return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
    };
    for (const [foreground, background, minimum] of [
      ["text-primary", "page-bg", 4.5], ["text-primary", "card-bg", 4.5],
      ["text-secondary", "surface-raised", 4.5], ["text-secondary", "sidebar-bg-secondary", 4.5],
      ["text-muted", "surface-hover", 4.5], ["brand-highlight", "sidebar-bg-secondary", 4.5],
      ["success", "success-bg", 4.5], ["warning", "warning-bg", 4.5], ["danger", "danger-bg", 4.5],
      ["text-on-brand", "brand-primary", 4.5], ["border-control", "surface-raised", 3],
      ["brand-highlight", "surface-raised", 3],
    ] as const) {
      const values = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
      expect((values[0] + 0.05) / (values[1] + 0.05), `${foreground}/${background}`).toBeGreaterThanOrEqual(minimum);
    }
  });

  it("Element Plus 表格保持 11px 正文与 12px 表头", () => {
    const css = readFileSync(resolve("src/styles/element.css"), "utf8");
    expect(css).toMatch(/\.el-table[^}]*font-size:\s*11px/s);
    expect(css).toMatch(/\.el-table__header[^}]*font-size:\s*12px/s);
  });
});
