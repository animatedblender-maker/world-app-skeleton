import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { ProfileService } from '../services/profile.service';

export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const profiles = inject(ProfileService);
  const router = inject(Router);

  const url = state.url || '/';

  // ✅ Always allow public routes (guard is not applied there now, but future-proof)
  if (url.startsWith('/auth') || url.startsWith('/reset-password')) {
    return true;
  }

  // 1) Must be logged in
  const user = await auth.getUser();
  if (!user) return router.parseUrl('/auth');

  // 2) Always allow profile setup route (so user can finish profile)
  if (url.startsWith('/profile-setup')) return true;

  // 3) If profile is missing, prefer allowing navigation over trapping
  //    established users in profile-setup due to environment/data drift.
  try {
    const { meProfile } = await profiles.meProfile();
    if (meProfile) return true;

    if (!meProfile) {
      const byId = await profiles.profileById(user.id);
      if (byId.profileById) return true;
    }

    console.warn('[authGuard] profile lookup returned null for authenticated user, allowing navigation', {
      userId: user.id,
      url,
    });
    return true;
  } catch (e) {
    console.warn('[authGuard] meProfile failed, allowing navigation:', e);
    return true;
  }

  return true;
};
