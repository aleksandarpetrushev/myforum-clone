import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RegistrationsComponent } from './registrations.component';

describe('RegistrationsComponent', () => {
  let fixture: ComponentFixture<RegistrationsComponent>;
  let http: HttpTestingController;

  const registration = {
    id: 9,
    status: 'confirmed',
    event_id: 6,
    event: { id: 6, title: 'Forum session 6: Energy', starts_at: '2026-10-23T09:00:00.000Z', location: 'Online' },
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RegistrationsComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(RegistrationsComponent);
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/registrations').flush({ data: [registration] });
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  it('cancels only after confirmation and ignores a second click', () => {
    clickButton('Cancel registration');
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Cancel your registration for Forum session 6: Energy?');
    http.expectNone('http://localhost:3000/api/registrations/cancel');

    clickButton('Confirm cancel');
    clickButton('Confirm cancel');
    fixture.detectChanges();

    const requests = http.match('http://localhost:3000/api/registrations/cancel');
    expect(requests.length).toBe(1);
    expect(fixture.nativeElement.textContent).toContain('Cancelling…');
    requests[0].flush({ ...registration, status: 'cancelled' });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Registration cancelled.');
    expect(fixture.nativeElement.textContent).toContain('cancelled');
    expect(fixture.nativeElement.textContent).not.toContain('Cancel registration');
  });

  function clickButton(name: string): void {
    const button = [...fixture.nativeElement.querySelectorAll('button')].find(
      (element: HTMLButtonElement) => element.textContent?.trim() === name,
    ) as HTMLButtonElement;
    button.click();
  }
});

describe('RegistrationsComponent hidden events', () => {
  let fixture: ComponentFixture<RegistrationsComponent>;
  let http: HttpTestingController;

  const registration = {
    id: 9,
    status: 'confirmed',
    event_id: 6,
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RegistrationsComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(RegistrationsComponent);
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/registrations').flush({ data: [registration] });
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  it('cancels a registration whose event is no longer viewable', () => {
    expect(fixture.nativeElement.querySelector('a')).toBeNull();
    expect(fixture.nativeElement.textContent).toContain('Registration');
    expect(fixture.nativeElement.textContent).not.toContain('Private clinic');

    clickButton('Cancel registration');
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Cancel this registration?');
    clickButton('Confirm cancel');

    const request = http.expectOne('http://localhost:3000/api/registrations/cancel');
    expect(request.request.body).toEqual({ event_id: 6 });
    request.flush({ ...registration, status: 'cancelled' });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Registration cancelled.');
  });

  function clickButton(name: string): void {
    const button = [...fixture.nativeElement.querySelectorAll('button')].find(
      (element: HTMLButtonElement) => element.textContent?.trim() === name,
    ) as HTMLButtonElement;
    button.click();
  }
});

describe('RegistrationsComponent cancelled events', () => {
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

  afterEach(() => http.verify());

  const event = { id: 6, title: 'Forum session 6: Energy', starts_at: '2026-11-23T09:00:00.000Z', location: 'Online' };

  it('shows Event cancelled from the event status, before the job reaches the registration', () => {
    http.expectOne('http://localhost:3000/api/me/registrations').flush({
      data: [{ id: 9, status: 'confirmed', cancelled_by: null, event_id: 6, event: { ...event, status: 'cancelled' } }],
    });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Event cancelled by the organizer');
    expect(fixture.nativeElement.textContent).not.toContain('Cancel registration');
  });

  it('shows Cancelled by the organizer once the registration is cancelled', () => {
    http.expectOne('http://localhost:3000/api/me/registrations').flush({
      data: [{ id: 9, status: 'cancelled', cancelled_by: 'organizer', event_id: 6, event: null }],
    });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Cancelled by the organizer');
  });
});
