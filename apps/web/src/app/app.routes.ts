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
    path: 'confirm-email',
    loadComponent: () =>
      import('./pages/confirm-email.page').then((m) => m.ConfirmEmailPageComponent),
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
    path: 'anonymous',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/anonymous.page').then((m) => m.AnonymousPageComponent),
  },
  // Product UI name is Masquerade (iOS MatteryaCopy.anonymous); route alias.
  {
    path: 'masquerade',
    redirectTo: 'anonymous',
    pathMatch: 'full',
  },
  // Globe tab replaced by Masquerade — keep modules on disk, unused.
  {
    path: 'globe',
    redirectTo: 'anonymous',
    pathMatch: 'full',
  },
  {
    path: 'globe-cesium',
    redirectTo: 'anonymous',
    pathMatch: 'full',
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
    path: 'edit-profile',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/edit-profile.page').then((m) => m.EditProfilePageComponent),
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
    path: 'studio',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./pages/studio/studio-shell.page').then((m) => m.StudioShellPageComponent),
    children: [
      {
        path: '',
        loadComponent: () =>
          import('./pages/studio/studio-dashboard.page').then(
            (m) => m.StudioDashboardPageComponent
          ),
      },
      {
        path: 'content',
        loadComponent: () =>
          import('./pages/studio/studio-content.page').then((m) => m.StudioContentPageComponent),
      },
      {
        path: 'content/:id',
        loadComponent: () =>
          import('./pages/studio/studio-video.page').then((m) => m.StudioVideoPageComponent),
      },
      {
        path: 'audience',
        loadComponent: () =>
          import('./pages/studio/studio-audience.page').then((m) => m.StudioAudiencePageComponent),
      },
    ],
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
      import('./pages/edit-profile.page').then((m) => m.EditProfilePageComponent),
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
