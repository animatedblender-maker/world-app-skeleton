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
      import('./pages/feed.page').then((m) => m.FeedPageComponent),
  },
  {
    path: 'feed',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/feed.page').then((m) => m.FeedPageComponent),
  },
  {
    path: 'hubs',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/hubs.page').then((m) => m.HubsPageComponent),
  },
  {
    path: 'hubs/watch/:id',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/hubs-watch.page').then((m) => m.HubsWatchPageComponent),
  },
  {
    path: 'play/watch/:id',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/hubs-watch.page').then((m) => m.HubsWatchPageComponent),
  },
  {
    path: 'hubs/channel/:id',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/hubs-channel.page').then((m) => m.HubsChannelPageComponent),
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
    path: 'profile',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/owner-profile.page').then((m) => m.OwnerProfilePageComponent),
  },
  {
    path: 'settings',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/account-settings.page').then((m) => m.AccountSettingsPageComponent),
  },
  {
    path: 'account',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/account-settings.page').then((m) => m.AccountSettingsPageComponent),
  },
  {
    path: 'search',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/search.page').then((m) => m.SearchPageComponent),
  },
  {
    path: 'people',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/people.page').then((m) => m.PeoplePageComponent),
  },
  {
    path: 'ads',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/ads.page').then((m) => m.AdsPageComponent),
  },
  {
    path: 'reels/:country',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/reels.page').then((m) => m.ReelsPageComponent),
  },
  {
    path: 'sparks/:country',
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
    path: 'news/:id',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/news.page').then((m) => m.NewsPageComponent),
  },
  {
    path: 'country/:code',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/country-feed.page').then((m) => m.CountryFeedPageComponent),
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
      import('./pages/public-profile.page').then((m) => m.PublicProfilePageComponent),
  },
  {
    path: 'user-edit/:slug',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/profile.page').then((m) => m.ProfilePageComponent),
  },

  
  // Public legal pages (store listing / GDPR) — no auth
  {
    path: 'privacy',
    loadComponent: () =>
      import('./pages/privacy.page').then((m) => m.PrivacyPageComponent),
  },
  {
    path: 'legal/privacy',
    loadComponent: () =>
      import('./pages/privacy.page').then((m) => m.PrivacyPageComponent),
  },
  {
    path: 'legal',
    redirectTo: 'privacy',
    pathMatch: 'full',
  },
  {
    path: 'terms',
    loadComponent: () =>
      import('./pages/terms.page').then((m) => m.TermsPageComponent),
  },

  { path: '**', redirectTo: '' },
];
