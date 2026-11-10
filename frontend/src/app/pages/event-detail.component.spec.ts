import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { AuthService } from '../core/auth.service';
import { EventDetailComponent } from './event-detail.component';

describe('EventDetailComponent', () => {
  const api = 'http://localhost:3000';
  let fixture: ComponentFixture<EventDetailComponent>;
  let http: HttpTestingController;

  const published = {
    id: 5,
    title: 'Climate finance session',
    starts_at: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString(),
    ends_at: new Date(Date.now() + 3 * 24 * 3600 * 1000 + 3600 * 1000).toISOString(),
    location: 'Geneva',
    kind: 'in_person',
    capacity: 10,
    reserved_spots: 2,
    status: 'published',
    cancelled_at: null,
    organization: { id: 1, name: 'Atlas' },
    topics: [],
    description: 'A working session',
    speakers: [],
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [EventDetailComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        { provide: ActivatedRoute, useValue: { paramMap: of(convertToParamMap({ id: '5' })) } },
      ],
    }).compileComponents();

    TestBed.inject(AuthService).token.set('test-token');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  function render(event: object, adminOrganizations: { id: number; name: string }[]): void {
    fixture = TestBed.createComponent(EventDetailComponent);
    fixture.detectChanges();
    http.expectOne(`${api}/api/me/organizations`).flush({ data: adminOrganizations });
    http.expectOne(`${api}/api/events/5`).flush(event);
    fixture.detectChanges();
  }

  function button(label: string): HTMLButtonElement | undefined {
    const buttons = Array.from(fixture.nativeElement.querySelectorAll('button')) as HTMLButtonElement[];
    return buttons.find((candidate) => candidate.textContent?.trim() === label);
  }

  it('asks the organizer admin to confirm, sends one request, then shows the Cancelled label', () => {
    render(published, [{ id: 1, name: 'Atlas' }]);

    button('Cancel event')!.click();
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('This cannot be undone.');
    http.expectNone(`${api}/api/events/5/cancel`);

    button('Confirm cancel event')!.click();
    button('Confirm cancel event')?.click();
    const request = http.expectOne(`${api}/api/events/5/cancel`);
    expect(request.request.method).toBe('POST');
    request.flush({ ...published, status: 'cancelled', cancelled_at: '2026-10-28T10:00:00Z' });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Cancelled');
    expect(button('Cancel event')).toBeUndefined();
    expect(button('Register')).toBeUndefined();
  });

  it('does not offer cancel to someone who is not an admin of the organizer', () => {
    render(published, [{ id: 9, name: 'Other' }]);

    expect(button('Cancel event')).toBeUndefined();
    expect(button('Register')).toBeDefined();
  });

  it('shows a cancelled event with its date and no Register button', () => {
    render({ ...published, status: 'cancelled', cancelled_at: '2026-10-28T10:00:00Z' }, []);

    expect(fixture.nativeElement.textContent).toContain('Cancelled');
    expect(fixture.nativeElement.textContent).toContain('2026');
    expect(button('Register')).toBeUndefined();
  });
  describe('waitlist (MF-202)', () => {
    const full = { ...published, capacity: 10, reserved_spots: 10, my_registration: null };

    it('offers Join waitlist instead of Register when the event is full, then shows the place in line', () => {
      render(full, []);
      expect(button('Register')).toBeUndefined();

      button('Join waitlist')!.click();
      const join = http.expectOne(`${api}/api/registrations/waitlist`);
      expect(join.request.body).toEqual({ event_id: 5 });
      join.flush({ id: 40, status: 'waitlisted', event_id: 5, waitlist_position: 3 });
      http.expectOne(`${api}/api/events/5`).flush({ ...full, my_registration: { id: 40, status: 'waitlisted', waitlist_position: 3 } });
      fixture.detectChanges();

      expect(fixture.nativeElement.textContent).toContain('You are #3 in line.');
      expect(button('Join waitlist')).toBeUndefined();
      expect(button('Leave waitlist')).toBeDefined();
    });

    it('shows an offered seat with its deadline, and confirms it', () => {
      render({ ...full, my_registration: { id: 40, status: 'offered', offer_expires_at: '2026-11-12T18:00:00Z' } }, []);
      expect(fixture.nativeElement.textContent).toContain('A seat is held for you until');
      expect(button('Decline')).toBeDefined();

      button('Confirm seat')!.click();
      http.expectOne(`${api}/api/registrations/accept_offer`).flush({ id: 40, status: 'confirmed', event_id: 5 });
      http.expectOne(`${api}/api/events/5`).flush({ ...full, my_registration: { id: 40, status: 'confirmed' } });
      fixture.detectChanges();

      expect(fixture.nativeElement.textContent).toContain('You are registered.');
      expect(button('Confirm seat')).toBeUndefined();
    });

    it('declines an offered seat through the registration cancel', () => {
      render({ ...full, my_registration: { id: 40, status: 'offered', offer_expires_at: '2026-11-12T18:00:00Z' } }, []);

      button('Decline')!.click();
      http.expectOne(`${api}/api/registrations/cancel`).flush({ id: 40, status: 'cancelled', event_id: 5 });
      http.expectOne(`${api}/api/events/5`).flush({ ...full, my_registration: { id: 40, status: 'cancelled' } });
      fixture.detectChanges();

      expect(fixture.nativeElement.textContent).toContain('You declined the seat.');
      expect(button('Join waitlist')).toBeDefined();
    });

    it('lets someone in line register when a seat is free in the last hour', () => {
      render({ ...published, capacity: 10, reserved_spots: 9, my_registration: { id: 40, status: 'waitlisted', waitlist_position: 1 } }, []);

      expect(fixture.nativeElement.textContent).toContain('A seat is free.');
      expect(button('Register')).toBeDefined();
      expect(button('Leave waitlist')).toBeDefined();
    });

    it('shows a closed waitlist instead of a Join button in the last hour', () => {
      render({ ...full, starts_at: new Date(Date.now() + 30 * 60 * 1000).toISOString() }, []);

      expect(button('Join waitlist')).toBeUndefined();
      expect(fixture.nativeElement.textContent).toContain('its waitlist closed');
    });

    it("shows the organizer's admins the waitlist count", () => {
      render({ ...full, waitlist_count: 7 }, [{ id: 1, name: 'Atlas' }]);

      expect(fixture.nativeElement.textContent).toContain('7 on the waitlist');
    });
  });
});
