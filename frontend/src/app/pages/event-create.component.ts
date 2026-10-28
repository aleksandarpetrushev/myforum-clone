import { Component, effect, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AdminOrganizationsService } from '../core/admin-organizations.service';
import { ForumApi } from '../core/forum-api';
import { CreateEventRequest, EventVisibility, Organization, Topic, ValidationError } from '../core/models';

@Component({
  selector: 'app-event-create',
  imports: [ReactiveFormsModule],
  templateUrl: './event-create.component.html',
})
export class EventCreateComponent {
  private readonly api = inject(ForumApi);
  private readonly forms = inject(FormBuilder);
  private readonly router = inject(Router);
  readonly adminOrganizations = inject(AdminOrganizationsService);

  readonly topics = signal<Topic[]>([]);
  readonly allOrganizations = signal<Organization[]>([]);
  readonly selectedTopicIds = signal<Set<number>>(new Set());
  readonly selectedAllowedIds = signal<Set<number>>(new Set());
  readonly submitting = signal(false);
  readonly error = signal<string | null>(null);
  readonly fieldErrors = signal<Record<string, string[]>>({});
  private organizationsRequested = false;

  readonly form = this.forms.nonNullable.group({
    organizationId: [0, Validators.min(1)],
    title: ['', Validators.required],
    description: ['', Validators.required],
    location: ['', Validators.required],
    kind: ['in_person' as CreateEventRequest['kind']],
    capacity: [50, [Validators.required, Validators.min(1)]],
    startsAt: ['', Validators.required],
    endsAt: ['', Validators.required],
    visibility: ['public' as EventVisibility],
  });

  readonly visibility = toSignal(this.form.controls.visibility.valueChanges, { initialValue: 'public' as EventVisibility });

  constructor() {
    this.adminOrganizations.ensureLoaded();

    this.api.topics().subscribe({
      next: (response) => this.topics.set(response.data),
      error: () => this.error.set('Could not load topics'),
    });

    // Preselect the organization once the admin list arrives; most admins run only one.
    effect(() => {
      const organizations = this.adminOrganizations.organizations();
      if (organizations.length > 0 && this.form.controls.organizationId.value === 0) {
        this.form.controls.organizationId.setValue(organizations[0].id);
      }
    });

    // The full organization list is only needed for restricted events, so it loads the first time one is chosen.
    effect(() => {
      if (this.visibility() === 'organization_restricted' && !this.organizationsRequested) {
        this.organizationsRequested = true;
        this.api.organizations().subscribe({
          next: (response) => this.allOrganizations.set(response.data),
          error: () => this.error.set('Could not load organizations'),
        });
      }
    });
  }

  toggleTopic(id: number): void {
    this.selectedTopicIds.update((ids) => toggled(ids, id));
  }

  toggleAllowed(id: number): void {
    this.selectedAllowedIds.update((ids) => toggled(ids, id));
  }

  submit(status: CreateEventRequest['status']): void {
    if (this.submitting()) return;
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.error.set('Fill in every required field.');
      return;
    }

    const value = this.form.getRawValue();
    const restricted = value.visibility === 'organization_restricted';
    const body: CreateEventRequest = {
      organization_id: value.organizationId,
      title: value.title,
      description: value.description,
      location: value.location,
      kind: value.kind,
      capacity: value.capacity,
      // datetime-local has no zone: it is read as the browser's local time and sent as UTC.
      starts_at: new Date(value.startsAt).toISOString(),
      ends_at: new Date(value.endsAt).toISOString(),
      status,
      visibility: value.visibility,
      allowed_organization_ids: restricted ? [...this.selectedAllowedIds()] : [],
      topic_ids: [...this.selectedTopicIds()],
    };

    this.submitting.set(true);
    this.error.set(null);
    this.fieldErrors.set({});
    this.api.createEvent(body).subscribe({
      next: (event) => this.router.navigate(['/events', event.id]),
      error: (response) => {
        const failure = response?.error?.error as ValidationError | undefined;
        this.fieldErrors.set(failure?.details ?? {});
        this.error.set(failure?.message ?? 'Could not create the event');
        this.submitting.set(false);
      },
    });
  }

  errorsFor(field: string): string[] {
    return this.fieldErrors()[field] ?? [];
  }
}

function toggled(ids: Set<number>, id: number): Set<number> {
  const next = new Set(ids);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}
