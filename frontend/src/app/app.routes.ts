import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { DiscoveryComponent } from './pages/discovery.component';
import { EventDetailComponent } from './pages/event-detail.component';
import { LoginComponent } from './pages/login.component';
import { NotificationsComponent } from './pages/notifications.component';
import { RegistrationsComponent } from './pages/registrations.component';
import { TopicsComponent } from './pages/topics.component';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  { path: 'events', component: DiscoveryComponent, canActivate: [authGuard] },
  { path: 'events/:id', component: EventDetailComponent, canActivate: [authGuard] },
  { path: 'registrations', component: RegistrationsComponent, canActivate: [authGuard] },
  { path: 'topics', component: TopicsComponent, canActivate: [authGuard] },
  { path: 'notifications', component: NotificationsComponent, canActivate: [authGuard] },
  { path: '', pathMatch: 'full', redirectTo: 'events' },
];
