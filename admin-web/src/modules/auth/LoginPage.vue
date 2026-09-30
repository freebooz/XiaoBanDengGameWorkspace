<script setup lang="ts">
import { useRoute, useRouter } from "vue-router";
import BrandLogo from "../../components/BrandLogo.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import { useAuthStore } from "../../app/store/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const isDevelopment = import.meta.env.DEV;

function loginDevelopment(): void {
  auth.loginDevelopment();
  const redirect = typeof route.query.redirect === "string" ? route.query.redirect : "/dashboard";
  void router.push(redirect);
}
</script>

<template>
  <main class="login-page">
    <section class="login-visual">
      <div class="login-visual__inner">
        <BrandLogo :show-subtitle="false" />
        <div class="login-kicker">Freebooz Studio · 小板凳游戏平台</div>
        <h1>让每一场对局<br />都被清晰运营。</h1>
        <p>
          统一查看账号、游戏、规则版本、实时房间与对局数据，
          为小板凳游戏家族提供稳定、可追溯的运营工作台。
        </p>
        <div class="login-feature-grid">
          <div><strong>统一</strong><span>账号与产品视图</span></div>
          <div><strong>实时</strong><span>房间与服务健康</span></div>
          <div><strong>可追溯</strong><span>对局与规则版本</span></div>
        </div>
      </div>
    </section>

    <section class="login-form-zone">
      <div class="login-card">
        <div class="login-card__top">
          <BrandLogo />
          <DevelopmentBadge v-if="isDevelopment" />
        </div>
        <div class="login-card__heading">
          <h2>管理员登录</h2>
          <p>登录小板凳游戏运营平台</p>
        </div>

        <el-alert
          v-if="isDevelopment"
          title="当前为开发环境，仅用于本地联调与人工验收。"
          type="warning"
          :closable="false"
          show-icon
        />

        <el-button
          v-if="isDevelopment"
          data-testid="development-login"
          class="development-login"
          type="primary"
          size="large"
          @click="loginDevelopment"
        >
          开发管理员登录
        </el-button>

        <el-empty
          v-else
          :image-size="64"
          description="正式管理员认证服务待接入"
        />

        <div class="login-card__footer">
          <span>小板凳统一运营后台</span>
          <span>Freebooz Studio</span>
        </div>
      </div>
    </section>
  </main>
</template>

<style scoped>
.login-page {
  width: 100%;
  min-height: 100vh;
  display: grid;
  grid-template-columns: minmax(520px, 1.18fr) minmax(480px, .82fr);
  background: var(--xbd-page-bg);
}
.login-visual {
  position: relative;
  overflow: hidden;
  display: flex;
  align-items: center;
  padding: 72px clamp(52px, 7vw, 112px);
  color: #fff9f2;
  background:
    radial-gradient(circle at 26% 22%, rgba(240,180,90,.22), transparent 32%),
    radial-gradient(circle at 72% 76%, rgba(212,138,58,.14), transparent 28%),
    linear-gradient(145deg, #181411 0%, #231b16 58%, #312219 100%);
}
.login-visual::after {
  position: absolute;
  right: -120px;
  bottom: -140px;
  width: 430px;
  height: 430px;
  border: 1px solid rgba(240,180,90,.14);
  border-radius: 50%;
  box-shadow: 0 0 0 56px rgba(240,180,90,.025), 0 0 0 116px rgba(240,180,90,.018);
  content: "";
}
.login-visual__inner { position: relative; z-index: 1; max-width: 620px; }
.login-kicker { margin-top: 72px; color: #c6ad94; font-size: 12px; letter-spacing: .12em; }
.login-visual h1 { margin: 18px 0 20px; font-size: clamp(42px, 4vw, 64px); line-height: 1.18; font-weight: 700; letter-spacing: -.02em; }
.login-visual p { max-width: 540px; margin: 0; color: #bcae9f; font-size: 15px; line-height: 1.85; }
.login-feature-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin-top: 46px; }
.login-feature-grid div { padding: 18px; border: 1px solid rgba(255,255,255,.08); border-radius: 14px; background: rgba(255,255,255,.035); backdrop-filter: blur(8px); }
.login-feature-grid strong, .login-feature-grid span { display: block; }
.login-feature-grid strong { color: var(--xbd-brand-highlight); font-size: 18px; }
.login-feature-grid span { margin-top: 6px; color: #a9998a; font-size: 11px; }
.login-form-zone { display: grid; place-items: center; padding: 50px; background: #f8f5f1; }
.login-card { width: min(430px, 100%); padding: 30px; border: 1px solid var(--xbd-border); border-radius: 20px; background: rgba(255,253,252,.96); box-shadow: 0 24px 70px rgba(75,49,28,.10); }
.login-card__top { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.login-card__heading { margin: 46px 0 24px; }
.login-card__heading h2 { margin: 0; font-size: 25px; font-weight: 700; }
.login-card__heading p { margin: 8px 0 0; color: var(--xbd-text-secondary); font-size: 12px; }
.development-login { width: 100%; height: 44px; margin-top: 18px; font-weight: 650; letter-spacing: .04em; }
.login-card__footer { display: flex; justify-content: space-between; margin-top: 34px; padding-top: 18px; border-top: 1px solid var(--xbd-border); color: #9a9087; font-size: 10px; }
@media (max-width: 1180px) {
  .login-page { grid-template-columns: 1fr 480px; }
  .login-visual { padding: 56px; }
  .login-feature-grid { grid-template-columns: 1fr; }
}
</style>
