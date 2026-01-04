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

  // 3) If profile incomplete, force setup
  try {
    const { meProfile } = await profiles.meProfile();
    if (!profiles.isComplete(meProfile)) {
      return router.parseUrl('/profile-setup');
    }
  } catch (e) {
    // MVP choice: don't lock user out if API/profile query fails
    console.warn('[authGuard] meProfile failed, allowing navigation:', e);
    return true;
  }

  return true;
};
