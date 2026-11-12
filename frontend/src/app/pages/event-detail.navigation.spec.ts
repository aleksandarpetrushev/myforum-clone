import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, ParamMap, convertToParamMap, provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';
import { AuthService } from '../core/auth.service';
import { EventDetailComponent } from './event-detail.component';

// The router reuses EventDetailComponent when only :id changes, so this drives the id by hand.
describe('EventDetailComponent moving between events', () => {
  const api = 'http://localhost:3000';
  const params = new BehaviorSubject<ParamMap>(convertToParamMap({ id: '5' }));
  let http: HttpTestingController;

  function draft(id: number) {
    return { id, title: `Draft ${id}`, starts_at: new Date(Date.now() + 86_400_000).toISOString(),
      ends_at: new Date(Date.now() + 90_000_000).toISOString(), location: 'Geneva', kind: 'in_person', capacity: 10,
      reserved_spots: 0, status: 'draft', cancelled_at: null, organization: { id: 1, name: 'Atlas' }, topics: [],
      description: 'Talk', speakers: [], my_registration: null };
  }

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [EventDetailComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        { provide: ActivatedRoute, useValue: { paramMap: params } },
      ],
    }).compileComponents();
    TestBed.inject(AuthService).token.set('test-token');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it("does not show one draft's publish errors on the next event", () => {
    const fixture = TestBed.createComponent(EventDetailComponent);
    fixture.detectChanges();
    http.expectOne(`${api}/api/me/organizations`).flush({ data: [{ id: 1, name: 'Atlas' }] });
    http.expectOne(`${api}/api/events/5`).flush(draft(5));
    fixture.detectChanges();

    const publish = [...fixture.nativeElement.querySelectorAll('button')].find(
      (b: HTMLButtonElement) => b.textContent?.trim() === 'Publish',
    ) as HTMLButtonElement;
    publish.click();
    http.expectOne(`${api}/api/events/5/publish`).flush(
      { error: { details: { starts_at: ['has already passed, so the event cannot be published'] } } },
      { status: 422, statusText: 'Unprocessable Entity' },
    );
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Start time has already passed');

    params.next(convertToParamMap({ id: '6' }));
    http.expectOne(`${api}/api/events/6`).flush(draft(6));
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Draft 6');
    expect(fixture.nativeElement.textContent).not.toContain('Start time has already passed');
  });
});
