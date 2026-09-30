import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("小板凳运营后台设计变量", () => {
  it("固定使用品牌主色、侧栏色和页面背景色", () => {
    const css = readFileSync(resolve("src/styles/tokens.css"), "utf8");
    expect(css).toContain("#D48A3A");
    expect(css).toContain("#181411");
    expect(css).toContain("#F5F2ED");
  });

  it("Element Plus 表格保持 11px 正文与 12px 表头", () => {
    const css = readFileSync(resolve("src/styles/element.css"), "utf8");
    expect(css).toMatch(/\.el-table[^}]*font-size:\s*11px/s);
    expect(css).toMatch(/\.el-table__header[^}]*font-size:\s*12px/s);
  });
});
