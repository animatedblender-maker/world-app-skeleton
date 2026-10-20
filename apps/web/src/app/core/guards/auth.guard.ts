import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { ProfileService } from '../services/profile.service';

export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const profiles = inject(ProfileService);
  const router = inject(Router);

  const url = state.url || '/';

  if (url.startsWith('/auth') || url.startsWith('/reset-password')) {
    return true;
  }

  const user = await auth.getUser();
  if (!user) return router.parseUrl('/auth');

  if (url.startsWith('/profile-setup')) return true;

  try {
    const { meProfile } = await profiles.meProfile();
    if (meProfile) {
      // Existing users missing birthdate (or core identity) must finish setup.
      if (!profiles.isComplete(meProfile)) {
        return router.parseUrl('/profile-setup');
      }
      return true;
    }

    const byId = await profiles.profileById(user.id);
    if (byId.profileById) {
      if (!profiles.isComplete(byId.profileById)) {
        return router.parseUrl('/profile-setup');
      }
      return true;
    }

    // No profile row yet — send to setup (full form for new users).
    return router.parseUrl('/profile-setup');
  } catch (e) {
    console.warn('[authGuard] meProfile failed, allowing navigation:', e);
    return true;
  }
};
