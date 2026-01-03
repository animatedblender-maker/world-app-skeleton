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
  { path: '**', redirectTo: '' },
];
