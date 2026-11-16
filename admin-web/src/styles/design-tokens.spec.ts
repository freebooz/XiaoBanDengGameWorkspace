import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("小板凳运营后台设计变量", () => {
  it("使用暖深色背景、奶油色前景和琥珀色品牌点缀", () => {
    const css = readFileSync(resolve("src/styles/tokens.css"), "utf8");
    expect(css).toContain("#D48A3A");
    expect(css).toContain("--xbd-page-bg: #17120E");
    expect(css).toContain("--xbd-text-primary: #F4E8D8");
  });

  it("正文、次要文字和状态色在常见深色背景上至少达到 4.5:1", () => {
    const css = readFileSync(resolve("src/styles/tokens.css"), "utf8");
    const luminance = (token: string) => {
      const color = css.match(new RegExp(`--xbd-${token}: #([a-f0-9]{6})\\b`, "i"))![1];
      const rgb = [0, 2, 4].map((index) => Number.parseInt(color.slice(index, index + 2), 16) / 255)
        .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
      return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
    };
    for (const [text, background] of [
      ["text-primary", "page-bg"], ["text-primary", "card-bg"], ["text-secondary", "surface-raised"],
      ["success", "success-bg"], ["warning", "warning-bg"], ["danger", "danger-bg"],
      ["text-on-brand", "brand-primary"],
    ]) {
      const values = [luminance(text), luminance(background)].sort((a, b) => b - a);
      expect((values[0] + 0.05) / (values[1] + 0.05), `${text}/${background}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it("Element Plus 表格保持 11px 正文与 12px 表头", () => {
    const css = readFileSync(resolve("src/styles/element.css"), "utf8");
    expect(css).toMatch(/\.el-table[^}]*font-size:\s*11px/s);
    expect(css).toMatch(/\.el-table__header[^}]*font-size:\s*12px/s);
  });
});
