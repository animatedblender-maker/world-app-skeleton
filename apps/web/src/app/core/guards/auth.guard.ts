import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { ProfileService } from '../services/profile.service';

export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const profiles = inject(ProfileService);
  const router = inject(Router);

  // 1) Must be logged in
  const user = await auth.getUser();
  if (!user) return router.parseUrl('/auth');

  // 2) Always allow profile setup route
  if (state.url.startsWith('/profile-setup')) return true;

  // 3) If profile incomplete, force setup
  try {
    const { meProfile } = await profiles.meProfile();
    if (!profiles.isComplete(meProfile)) {
      return router.parseUrl('/profile-setup');
    }
  } catch {
    // If API is down / query missing, don't lock user out of the app.
    // (We’ll harden this once backend Step 2.1 is finalized.)
    return true;
  }

  return true;
};
