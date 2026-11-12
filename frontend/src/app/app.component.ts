import { Component, effect, inject } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { AdminOrganizationsService } from './core/admin-organizations.service';
import { AuthService } from './core/auth.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink],
  templateUrl: './app.component.html',
})
export class AppComponent {
  readonly auth = inject(AuthService);
  readonly adminOrganizations = inject(AdminOrganizationsService);

  constructor() {
    // "My drafts" is for organization admins only; load which organizations they administer on each sign-in.
    effect(() => {
      if (this.auth.token()) this.adminOrganizations.ensureLoaded();
    });
  }

  logout(): void {
    this.auth.clear();
  }
}
