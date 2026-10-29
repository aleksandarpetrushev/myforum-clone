import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RegistrationsComponent } from './registrations.component';

const url = 'http://localhost:3000/api/me/registrations';

function eventSummary(id: number, title: string, startsAt: string, endsAt: string, status = 'published') {
  return { id, title, starts_at: startsAt, ends_at: endsAt, location: 'Online', status };
}

describe('RegistrationsComponent', () => {
  let fixture: ComponentFixture<RegistrationsComponent>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RegistrationsComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(RegistrationsComponent);
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
  });

  afterEach(() => {
    http.verify();
    jasmine.clock().uninstall();
  });

  function respond(body: { upcoming: object[]; past: object[] }): void {
    http.expectOne(url).flush(body);
    fixture.detectChanges();
  }

  function text(): string {
    return fixture.nativeElement.textContent;
  }

  function section(heading: string): HTMLElement {
    return [...fixture.nativeElement.querySelectorAll('section')].find((element: HTMLElement) =>
      element.querySelector('h2')?.textContent?.trim() === heading,
    ) as HTMLElement;
  }

  function buttonNamed(name: string, within: HTMLElement = fixture.nativeElement): HTMLButtonElement | undefined {
    return [...within.querySelectorAll('button')].find(
      (element: HTMLButtonElement) => element.textContent?.trim() === name,
    ) as HTMLButtonElement | undefined;
  }

  const tomorrow = { id: 9, status: 'confirmed', cancelled_by: null, event_id: 6,
    event: eventSummary(6, 'Forum session 6: Energy', '2026-11-23T09:00:00.000Z', '2026-11-23T10:00:00.000Z') };

  it('renders Upcoming then Past, keeping the order the server sent', () => {
    respond({
      upcoming: [tomorrow, { ...tomorrow, id: 10, event_id: 7, event: eventSummary(7, 'Later session', '2026-11-25T09:00:00.000Z', '2026-11-25T10:00:00.000Z') }],
      past: [{ ...tomorrow, id: 11, event_id: 8, event: eventSummary(8, 'Old session', '2026-09-01T09:00:00.000Z', '2026-09-01T10:00:00.000Z') }],
    });

    const headings = [...fixture.nativeElement.querySelectorAll('h2')].map((h: HTMLElement) => h.textContent?.trim());
    expect(headings.slice(0, 2)).toEqual(['Upcoming', 'Past']);
    const upcomingTitles = [...section('Upcoming').querySelectorAll('h3')].map((h: HTMLElement) => h.textContent?.trim());
    expect(upcomingTitles).toEqual(['Forum session 6: Energy', 'Later session']);
    expect(section('Past').textContent).toContain('Old session');
  });

  it('shows an empty state for each empty section', () => {
    respond({ upcoming: [], past: [] });

    expect(section('Upcoming').textContent).toContain('No upcoming events');
    expect(section('Past').textContent).toContain('No past events');
  });

  it('marks an upcoming event as Happening now only between its start and end', () => {
    jasmine.clock().install();
    jasmine.clock().mockDate(new Date('2026-11-23T09:30:00.000Z'));
    respond({
      upcoming: [tomorrow, { ...tomorrow, id: 10, event_id: 7, event: eventSummary(7, 'Later session', '2026-11-25T09:00:00.000Z', '2026-11-25T10:00:00.000Z') }],
      past: [],
    });

    const cards = [...section('Upcoming').querySelectorAll('article')] as HTMLElement[];
    expect(cards[0].textContent).toContain('Happening now');
    expect(cards[1].textContent).not.toContain('Happening now');
  });

  it('offers Cancel registration only in Upcoming', () => {
    respond({ upcoming: [tomorrow], past: [{ ...tomorrow, id: 11, event_id: 8, event: eventSummary(8, 'Old session', '2026-09-01T09:00:00.000Z', '2026-09-01T10:00:00.000Z') }] });

    expect(buttonNamed('Cancel registration', section('Upcoming'))).toBeDefined();
    expect(buttonNamed('Cancel registration', section('Past'))).toBeUndefined();
  });

  it('does not offer Cancel registration for an event that is happening now', () => {
    jasmine.clock().install();
    jasmine.clock().mockDate(new Date('2026-11-23T09:30:00.000Z'));
    respond({
      upcoming: [tomorrow, { ...tomorrow, id: 10, event_id: 7, event: eventSummary(7, 'Later session', '2026-11-25T09:00:00.000Z', '2026-11-25T10:00:00.000Z') }],
      past: [],
    });

    const cards = [...section('Upcoming').querySelectorAll('article')] as HTMLElement[];
    expect(buttonNamed('Cancel registration', cards[0])).toBeUndefined();
    expect(buttonNamed('Cancel registration', cards[1])).toBeDefined();
  });

  it('labels past rows Cancelled, Event cancelled and Registration failed', () => {
    respond({
      upcoming: [],
      past: [
        { ...tomorrow, id: 21, status: 'cancelled', cancelled_by: 'participant' },
        { ...tomorrow, id: 22, status: 'cancelled', cancelled_by: 'organizer' },
        { ...tomorrow, id: 23, status: 'confirmed', event: { ...tomorrow.event, status: 'cancelled' } },
        { ...tomorrow, id: 24, status: 'failed' },
      ],
    });

    const labels = [...section('Past').querySelectorAll('article strong')].map((s: Element) => s.textContent?.trim());
    expect(labels).toEqual(['Cancelled', 'Event cancelled', 'Event cancelled', 'Registration failed']);
  });

  it('cancels only after confirmation, ignores a second click, then reloads so the row moves to Past', () => {
    respond({ upcoming: [tomorrow], past: [] });

    buttonNamed('Cancel registration')!.click();
    fixture.detectChanges();
    expect(text()).toContain('Cancel your registration for Forum session 6: Energy?');
    http.expectNone('http://localhost:3000/api/registrations/cancel');

    buttonNamed('Confirm cancel')!.click();
    buttonNamed('Confirm cancel')?.click();
    fixture.detectChanges();
    const requests = http.match('http://localhost:3000/api/registrations/cancel');
    expect(requests.length).toBe(1);
    expect(text()).toContain('Cancelling…');
    requests[0].flush({ ...tomorrow, status: 'cancelled', cancelled_by: 'participant' });
    fixture.detectChanges();

    respond({ upcoming: [], past: [{ ...tomorrow, status: 'cancelled', cancelled_by: 'participant' }] });
    expect(text()).toContain('Registration cancelled.');
    expect(section('Upcoming').textContent).toContain('No upcoming events');
    expect(section('Past').textContent).toContain('Cancelled');
  });

  it('cancels a registration whose event is no longer viewable', () => {
    const hidden = { id: 9, status: 'confirmed', cancelled_by: null, event_id: 6 };
    respond({ upcoming: [hidden], past: [] });

    expect(section('Upcoming').querySelector('a')).toBeNull();
    expect(section('Upcoming').textContent).toContain('Registration');

    buttonNamed('Cancel registration')!.click();
    fixture.detectChanges();
    expect(text()).toContain('Cancel this registration?');
    buttonNamed('Confirm cancel')!.click();

    const request = http.expectOne('http://localhost:3000/api/registrations/cancel');
    expect(request.request.body).toEqual({ event_id: 6 });
    request.flush({ ...hidden, status: 'cancelled' });
    respond({ upcoming: [], past: [{ ...hidden, status: 'cancelled', cancelled_by: 'participant' }] });

    expect(text()).toContain('Registration cancelled.');
  });
});
