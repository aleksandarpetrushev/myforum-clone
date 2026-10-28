import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { EventCreateComponent } from './event-create.component';

describe('EventCreateComponent', () => {
  let fixture: ComponentFixture<EventCreateComponent>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [EventCreateComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    TestBed.inject(AuthService).token.set('test-token');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  function render(adminOrganizations: { id: number; name: string }[]): void {
    fixture = TestBed.createComponent(EventCreateComponent);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/organizations').flush({ data: adminOrganizations });
    http.expectOne('http://localhost:3000/api/topics').flush({ data: [{ id: 3, name: 'Climate', slug: 'climate' }] });
    fixture.detectChanges();
  }

  function fillRequiredFields(): void {
    fixture.componentInstance.form.patchValue({
      title: 'Financing the energy transition',
      description: 'A working session',
      location: 'Geneva',
      capacity: 80,
      startsAt: '2026-11-20T09:00',
      endsAt: '2026-11-20T10:30',
    });
    fixture.detectChanges();
  }

  function button(label: string): HTMLButtonElement {
    const buttons = Array.from(fixture.nativeElement.querySelectorAll('button')) as HTMLButtonElement[];
    const match = buttons.find((candidate) => candidate.textContent?.trim() === label);
    if (!match) throw new Error(`No button labelled ${label}`);
    return match;
  }

  it('tells a user with no admin organizations that only admins can create events', () => {
    render([]);

    expect(fixture.nativeElement.textContent).toContain('Only organization admins can create events.');
    expect(fixture.nativeElement.querySelector('form')).toBeNull();
  });

  it('disables the button and shows Creating... until the request fails, then shows the field error', () => {
    render([{ id: 1, name: 'Atlas' }]);
    fillRequiredFields();

    button('Publish event').click();
    fixture.detectChanges();

    const request = http.expectOne('http://localhost:3000/api/events');
    expect(request.request.method).toBe('POST');
    expect(request.request.body.event).toEqual(
      jasmine.objectContaining({ organization_id: 1, status: 'published', visibility: 'public', allowed_organization_ids: [] }),
    );
    const submitting = button('Creating...');
    expect(submitting.disabled).toBeTrue();

    button('Creating...').click();
    http.expectNone('http://localhost:3000/api/events');

    request.flush(
      { error: { code: 'validation_failed', message: 'Validation failed', details: { ends_at: ['must be after starts_at'] } } },
      { status: 422, statusText: 'Unprocessable Entity' },
    );
    fixture.detectChanges();

    expect(button('Publish event').disabled).toBeFalse();
    expect(fixture.nativeElement.textContent).toContain('End time must be after starts_at');
  });

  it('shows the allowed organizations picker only for restricted events', () => {
    render([{ id: 1, name: 'Atlas' }]);
    expect(fixture.nativeElement.textContent).not.toContain('Allowed organizations');
    http.expectNone('http://localhost:3000/api/organizations');

    fixture.componentInstance.form.controls.visibility.setValue('organization_restricted');
    fixture.detectChanges();
    http
      .expectOne('http://localhost:3000/api/organizations')
      .flush({ data: [{ id: 1, name: 'Atlas' }, { id: 2, name: 'Borealis' }] });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Allowed organizations');
    expect(fixture.nativeElement.textContent).toContain('Borealis');

    fixture.componentInstance.form.controls.visibility.setValue('public');
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).not.toContain('Allowed organizations');
  });
});
