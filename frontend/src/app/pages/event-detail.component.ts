import { Component, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { catchError, of, switchMap } from 'rxjs';
import { ForumApi } from '../core/forum-api';
import { EventSummary } from '../core/models';

@Component({
  selector: 'app-event-detail',
  imports: [RouterLink],
  templateUrl: './event-detail.component.html',
})
export class EventDetailComponent {
  private readonly api = inject(ForumApi);
  private readonly route = inject(ActivatedRoute);

  readonly event = signal<EventSummary | null>(null);
  readonly error = signal<string | null>(null);
  readonly message = signal<string | null>(null);

  constructor() {
    this.route.paramMap
      .pipe(
        switchMap((params) => this.api.event(Number(params.get('id')))),
        catchError(() => {
          this.error.set('Event not found');
          return of(null);
        }),
        takeUntilDestroyed(inject(DestroyRef)),
      )
      .subscribe((event) => this.event.set(event));
  }

  register(): void {
    const event = this.event();
    if (!event) return;
    this.api.register(event.id).subscribe({
      next: () => this.message.set('You are registered.'),
      error: (error) => this.message.set(error?.error?.error?.message ?? 'Registration failed'),
    });
  }
}
