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

  constructor() {
    this.api.registrations().subscribe({
      next: (response) => this.registrations.set(response.data),
      error: () => this.error.set('Could not load registrations'),
    });
  }
}
