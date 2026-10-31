import { Routes } from '@angular/router';
import { AuthPageComponent } from './pages/auth.page';
import { GlobePageComponent } from './pages/globe.page';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  { path: 'auth', component: AuthPageComponent },
  { path: '', component: GlobePageComponent, canActivate: [authGuard] },
  { path: '**', redirectTo: '' },
];
