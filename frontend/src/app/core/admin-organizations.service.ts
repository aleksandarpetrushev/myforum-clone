import { Injectable, computed, inject, signal } from '@angular/core';
import { AuthService } from './auth.service';
import { ForumApi } from './forum-api';
import { Organization } from './models';

// The organizations the signed-in user administers, shared by the events page and the create page.
// Loaded once per signed-in user; a different token loads again so a new login never sees the last user's list.
@Injectable({ providedIn: 'root' })
export class AdminOrganizationsService {
  private readonly api = inject(ForumApi);
  private readonly auth = inject(AuthService);
  private loadedFor: string | null = null;

  readonly organizations = signal<Organization[]>([]);
  readonly loaded = signal(false);
  readonly canCreate = computed(() => this.organizations().length > 0);

  ensureLoaded(): void {
    const token = this.auth.token();
    if (!token || token === this.loadedFor) return;
    this.loadedFor = token;
    // Drop the previous user's list at once, so nothing renders from it while the new one loads.
    this.organizations.set([]);
    this.loaded.set(false);
    this.api.adminOrganizations().subscribe({
      next: (response) => {
        if (this.loadedFor !== token) return; // a reply for an earlier sign-in arrived late
        this.organizations.set(response.data);
        this.loaded.set(true);
      },
      error: () => {
        if (this.loadedFor !== token) return;
        this.loaded.set(true);
        this.loadedFor = null;
      },
    });
  }
}
