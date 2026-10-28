import { Component, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, debounceTime, of, startWith, switchMap, tap } from 'rxjs';
import { AdminOrganizationsService } from '../core/admin-organizations.service';
import { EventSummary, Topic } from '../core/models';
import { ForumApi } from '../core/forum-api';

@Component({
  selector: 'app-discovery',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './discovery.component.html',
})
export class DiscoveryComponent {
  private readonly api = inject(ForumApi);
  private readonly forms = inject(FormBuilder);
  private readonly destroyRef = inject(DestroyRef);
  readonly adminOrganizations = inject(AdminOrganizationsService);

  readonly events = signal<EventSummary[]>([]);
  readonly topics = signal<Topic[]>([]);
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly form = this.forms.nonNullable.group({
    q: '',
    topicId: '',
    location: '',
  });

  constructor() {
    this.adminOrganizations.ensureLoaded();

    this.api.topics().pipe(takeUntilDestroyed()).subscribe({
      next: (response) => this.topics.set(response.data),
      error: () => this.error.set('Could not load topics'),
    });

    this.form.valueChanges
      .pipe(
        startWith(this.form.getRawValue()),
        debounceTime(200),
        tap(() => {
          this.loading.set(true);
          this.error.set(null);
        }),
        switchMap((value) =>
          this.api.events({ q: value.q, topicId: value.topicId, location: value.location }).pipe(
            catchError(() => {
              this.error.set('Could not load events');
              return of({ data: [] as EventSummary[] });
            }),
          ),
        ),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe((response) => {
        this.events.set(response.data);
        this.loading.set(false);
      });
  }
}
