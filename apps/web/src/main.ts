import { provideZonelessChangeDetection } from '@angular/core';
import { bootstrapApplication } from '@angular/platform-browser';
import { provideRouter } from '@angular/router';
import { routes } from './app/app.routes';
import { AppComponent } from './app/app';

// Explicit zoneless mode (no zone.js). Pages that set state after await must
// call ChangeDetectorRef.detectChanges() — Feed/Hubs already do.
bootstrapApplication(AppComponent, {
  providers: [provideZonelessChangeDetection(), provideRouter(routes)],
});
