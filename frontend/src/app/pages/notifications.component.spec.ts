import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { NotificationsComponent } from './notifications.component';

describe('NotificationsComponent', () => {
  let fixture: ComponentFixture<NotificationsComponent>;
  let http: HttpTestingController;

  const unread = {
    id: 2,
    kind: 'registration_confirmed',
    title: 'Registration confirmed',
    body: 'You are registered for the AI Forum.',
    read_at: null,
    created_at: '2026-10-21T10:30:00.000Z',
  };
  const read = {
    id: 1,
    kind: 'registration_cancelled',
    title: 'Registration cancelled',
    body: 'Your registration for the Climate Forum was cancelled.',
    read_at: '2026-10-20T10:30:00.000Z',
    created_at: '2026-10-20T10:30:00.000Z',
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [NotificationsComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    fixture = TestBed.createComponent(NotificationsComponent);
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/notification_preferences').flush({
      registration_confirmed_enabled: true,
      registration_cancelled_enabled: true,
      event_cancelled_enabled: true,
    });
    http.expectOne('http://localhost:3000/api/me/notifications').flush({
      data: [unread, read],
      unread_count: 2,
      next_cursor: 'cursor-2',
    });
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  it('shows the unread count and a blue dot only on unread notifications', () => {
    expect(fixture.nativeElement.textContent).toContain('2 unread');
    expect(fixture.nativeElement.querySelectorAll('.unread-dot').length).toBe(1);
  });

  it('marks one notification read from the dot and updates the count', () => {
    fixture.nativeElement.querySelector('.unread-dot').click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.unread-dot').disabled).toBe(true);

    const request = http.expectOne('http://localhost:3000/api/me/notifications/2/read');
    expect(request.request.method).toBe('POST');
    request.flush({ ...unread, read_at: '2026-10-21T11:00:00.000Z', unread_count: 1 });
    fixture.detectChanges();

    expect(fixture.nativeElement.querySelector('.unread-dot')).toBeNull();
    expect(fixture.nativeElement.textContent).toContain('1 unread');
  });

  it('disables mark all until the response clears every dot', () => {
    const button = buttonNamed('Mark all read');
    button.click();
    fixture.detectChanges();
    expect(button.disabled).toBe(true);

    const request = http.expectOne('http://localhost:3000/api/me/notifications/read_all');
    expect(request.request.method).toBe('POST');
    request.flush({ unread_count: 0 });
    fixture.detectChanges();

    expect(fixture.nativeElement.querySelector('.unread-dot')).toBeNull();
    expect(fixture.nativeElement.textContent).toContain('0 unread');
    expect(button.disabled).toBe(true);
  });

  it('loads the next page with the cursor', () => {
    buttonNamed('Older notifications').click();
    const request = http.expectOne((candidate) => candidate.url === 'http://localhost:3000/api/me/notifications');
    expect(request.request.params.get('cursor')).toBe('cursor-2');
    request.flush({ data: [], unread_count: 2, next_cursor: null });
    fixture.detectChanges();
  });

  it('restores a preference checkbox when the save fails', () => {
    const checkbox = fixture.nativeElement.querySelector('input[type="checkbox"]') as HTMLInputElement;
    checkbox.checked = false;
    checkbox.dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(checkbox.checked).toBe(false);

    const request = http.expectOne('http://localhost:3000/api/me/notification_preferences');
    request.flush('error', { status: 422, statusText: 'Unprocessable Entity' });
    fixture.detectChanges();

    expect(checkbox.checked).toBe(true);
    expect(fixture.nativeElement.textContent).toContain('Could not save notification preferences');
  });

  it('saves a preference change', () => {
    const checkbox = fixture.nativeElement.querySelector('input[type="checkbox"]') as HTMLInputElement;
    checkbox.checked = false;
    checkbox.dispatchEvent(new Event('change'));

    const request = http.expectOne('http://localhost:3000/api/me/notification_preferences');
    expect(request.request.method).toBe('PATCH');
    expect(request.request.body.notification_preference.registration_confirmed_enabled).toBe(false);
    request.flush({
      registration_confirmed_enabled: false,
      registration_cancelled_enabled: true,
      event_cancelled_enabled: true,
    });
    fixture.detectChanges();
    expect(checkbox.checked).toBe(false);
  });

  it('saves the event cancellations switch', () => {
    const label = [...fixture.nativeElement.querySelectorAll('label.preference')].find((element: HTMLElement) =>
      element.textContent?.includes('Event cancellations'),
    ) as HTMLElement;
    const checkbox = label.querySelector('input') as HTMLInputElement;
    expect(checkbox.checked).toBe(true);

    checkbox.checked = false;
    checkbox.dispatchEvent(new Event('change'));

    const request = http.expectOne('http://localhost:3000/api/me/notification_preferences');
    expect(request.request.body.notification_preference.event_cancelled_enabled).toBe(false);
    request.flush({ registration_confirmed_enabled: true, registration_cancelled_enabled: true, event_cancelled_enabled: false });
  });

  function buttonNamed(name: string): HTMLButtonElement {
    return [...fixture.nativeElement.querySelectorAll('button')].find(
      (element: HTMLButtonElement) => element.textContent?.trim() === name,
    ) as HTMLButtonElement;
  }
});
