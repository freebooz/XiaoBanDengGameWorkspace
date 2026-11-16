<script setup lang="ts">
import { watch } from "vue";
import { RouterView, useRouter } from "vue-router";
import { useAuthStore } from "./app/store/auth";

const auth = useAuthStore();
const router = useRouter();
watch(() => auth.isAuthenticated, (loggedIn) => {
  const route = router.currentRoute.value;
  if (!loggedIn && route.meta.requiresAuth) {
    void router.replace({ name: "login", query: { redirect: route.fullPath } });
  }
});
</script>

<template>
  <RouterView />
</template>
