import { DatePipe } from '@angular/common';
import { Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Observable, catchError, of, switchMap } from 'rxjs';
import { AdminOrganizationsService } from '../core/admin-organizations.service';
import { ForumApi } from '../core/forum-api';
import { EventSummary } from '../core/models';

@Component({
  selector: 'app-event-detail',
  imports: [RouterLink, DatePipe],
  templateUrl: './event-detail.component.html',
})
export class EventDetailComponent {
  private readonly api = inject(ForumApi);
  private readonly route = inject(ActivatedRoute);
  private readonly adminOrganizations = inject(AdminOrganizationsService);

  readonly event = signal<EventSummary | null>(null);
  readonly error = signal<string | null>(null);
  readonly message = signal<string | null>(null);
  readonly confirmingCancel = signal(false);
  readonly cancelling = signal(false);

  readonly cancelled = computed(() => this.event()?.status === 'cancelled');
  readonly full = computed(() => {
    const event = this.event();
    return !!event && event.reserved_spots >= event.capacity;
  });
  // The viewer's own registration, if it is still active: registered, waiting in line, or offered a seat.
  readonly mine = computed(() => {
    const registration = this.event()?.my_registration;
    return registration && ['confirmed', 'waitlisted', 'offered'].includes(registration.status) ? registration : null;
  });
  readonly busy = signal(false);
  // Only the organizer's admins may cancel, and only a published event that has not started.
  readonly canCancel = computed(() => {
    const event = this.event();
    if (!event || event.status !== 'published' || new Date(event.starts_at) <= new Date()) return false;
    return this.adminOrganizations.organizations().some((organization) => organization.id === event.organization.id);
  });

  constructor() {
    this.adminOrganizations.ensureLoaded();

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
    this.act((id) => this.api.register(id), 'You are registered.', 'Registration failed');
  }

  joinWaitlist(): void {
    this.act((id) => this.api.joinWaitlist(id), 'You joined the waitlist.', 'Could not join the waitlist');
  }

  acceptOffer(): void {
    this.act((id) => this.api.acceptOffer(id), 'Your seat is confirmed.', 'Could not confirm the seat');
  }

  // Leaving the line and declining an offer are both a cancel of the viewer's own registration.
  leave(done: string): void {
    this.act((id) => this.api.cancelRegistration(id), done, 'Could not do that');
  }

  // Each action reloads the event, so the seat count, the viewer's place in line and the buttons stay right.
  private act(call: (eventId: number) => Observable<unknown>, done: string, failed: string): void {
    const event = this.event();
    if (!event || this.busy()) return;
    this.busy.set(true);
    this.message.set(null);
    call(event.id)
      .pipe(switchMap(() => this.api.event(event.id)))
      .subscribe({
        next: (updated) => {
          this.event.set(updated);
          this.message.set(done);
          this.busy.set(false);
        },
        error: (error) => {
          this.message.set(error?.error?.error?.message ?? failed);
          this.busy.set(false);
        },
      });
  }

  askCancel(): void {
    if (this.cancelling()) return;
    this.message.set(null);
    this.confirmingCancel.set(true);
  }

  keepEvent(): void {
    if (this.cancelling()) return;
    this.confirmingCancel.set(false);
  }

  confirmCancel(): void {
    const event = this.event();
    if (!event || this.cancelling()) return;
    this.cancelling.set(true);
    this.api.cancelEvent(event.id).subscribe({
      next: (updated) => {
        this.event.set(updated);
        this.message.set('Event cancelled. Registrants are being notified.');
        this.confirmingCancel.set(false);
        this.cancelling.set(false);
      },
      error: (error) => {
        this.message.set(error?.error?.error?.message ?? 'Could not cancel the event');
        this.cancelling.set(false);
      },
    });
  }
}
