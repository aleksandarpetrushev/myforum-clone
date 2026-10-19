import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ForumApi } from '../core/forum-api';
import { Registration } from '../core/models';

@Component({
  selector: 'app-registrations',
  imports: [RouterLink],
  templateUrl: './registrations.component.html',
})
export class RegistrationsComponent {
  private readonly api = inject(ForumApi);
  readonly registrations = signal<Registration[]>([]);
  readonly error = signal<string | null>(null);
  readonly notice = signal<string | null>(null);
  readonly confirmingId = signal<number | null>(null);
  readonly cancellingId = signal<number | null>(null);

  constructor() {
    this.load();
  }

  askCancel(registration: Registration): void {
    if (this.cancellingId() !== null) return;
    this.notice.set(null);
    this.error.set(null);
    this.confirmingId.set(registration.id);
  }

  dismissConfirm(): void {
    if (this.cancellingId() !== null) return;
    this.confirmingId.set(null);
  }

  confirmCancel(registration: Registration): void {
    if (this.cancellingId() !== null) return;
    this.cancellingId.set(registration.id);
    this.error.set(null);
    this.notice.set(null);
    this.api.cancelRegistration(registration.event_id).subscribe({
      next: (updated) => {
        this.registrations.update((rows) =>
          rows.map((row) => (row.id === updated.id ? { ...row, status: updated.status } : row)),
        );
        this.notice.set('Registration cancelled.');
        this.confirmingId.set(null);
        this.cancellingId.set(null);
      },
      error: (error) => {
        this.error.set(error?.error?.error?.message ?? 'Could not cancel that registration');
        this.cancellingId.set(null);
      },
    });
  }

  private load(): void {
    this.api.registrations().subscribe({
      next: (response) => this.registrations.set(response.data),
      error: () => this.error.set('Could not load registrations'),
    });
  }
}
