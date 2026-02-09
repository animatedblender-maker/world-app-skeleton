import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  {
    path: 'auth',
    loadComponent: () =>
      import('./pages/auth.page').then((m) => m.AuthPageComponent),
  },
  {
    path: 'profile-setup',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/profile-setup.page').then((m) => m.ProfileSetupPageComponent),
  },
  {
    path: 'reset-password',
    loadComponent: () =>
      import('./pages/reset-password.page').then((m) => m.ResetPasswordPageComponent),
  },

  // ✅ NEW: /me must be BEFORE '**'
  {
    path: 'me',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/me.page').then((m) => m.MePageComponent),
  },

  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/globe.page').then((m) => m.GlobePageComponent),
  },
  {
    path: 'globe',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/globe.page').then((m) => m.GlobePageComponent),
  },
  {
    path: 'globe-cesium',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/globe-cesium.page').then((m) => m.GlobeCesiumPageComponent),
  },
  {
    path: 'messages',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/messages.page').then((m) => m.MessagesPageComponent),
  },
  {
    path: 'search',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/search.page').then((m) => m.SearchPageComponent),
  },
  {
    path: 'reels/:country',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/reels.page').then((m) => m.ReelsPageComponent),
  },
  {
    path: 'post/:id',
    loadComponent: () =>
      import('./pages/post.page').then((m) => m.PostPageComponent),
  },
  {
    path: 'ops-portal-2026',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/admin-presence.page').then((m) => m.AdminPresencePageComponent),
  },
  {
    path: 'admin-presence',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/admin-presence.page').then((m) => m.AdminPresencePageComponent),
  },
  {
    path: 'user/:slug',
    loadComponent: () =>
      import('./pages/profile.page').then((m) => m.ProfilePageComponent),
  },

  // ✅ wildcard ALWAYS last
  { path: '**', redirectTo: '' },
];
