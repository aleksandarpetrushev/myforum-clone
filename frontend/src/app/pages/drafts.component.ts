import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ForumApi } from '../core/forum-api';
import { EventSummary } from '../core/models';

// MF-105: an admin's drafts, which never appear in discovery.
@Component({
  selector: 'app-drafts',
  imports: [RouterLink],
  templateUrl: './drafts.component.html',
})
export class DraftsComponent {
  private readonly api = inject(ForumApi);
  readonly drafts = signal<EventSummary[]>([]);
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);

  constructor() {
    this.api.drafts().subscribe({
      next: (response) => {
        this.drafts.set(response.data);
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Could not load drafts');
        this.loading.set(false);
      },
    });
  }
}
