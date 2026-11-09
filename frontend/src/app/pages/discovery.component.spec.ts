import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { DiscoveryComponent } from './discovery.component';

describe('DiscoveryComponent', () => {
  let fixture: ComponentFixture<DiscoveryComponent>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [DiscoveryComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    TestBed.inject(AuthService).token.set('test-token');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  const recommendationsUrl = 'http://localhost:3000/api/me/recommendations';

  function event(id: number, title: string) {
    return { id, title, starts_at: '2026-11-23T09:00:00.000Z', ends_at: '2026-11-23T10:00:00.000Z', location: 'Geneva',
      kind: 'in_person', capacity: 10, reserved_spots: 0, status: 'published', organization: { id: 1, name: 'Atlas' }, topics: [] };
  }

  // Renders the page and answers every request except recommendations, which each test answers itself.
  function renderWithoutRecommendations(
    adminOrganizations: { id: number; name: string }[] = [],
    events: object[] = [],
  ): void {
    fixture = TestBed.createComponent(DiscoveryComponent);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/organizations').flush({ data: adminOrganizations });
    http.expectOne('http://localhost:3000/api/topics').flush({ data: [] });
    tick(200);
    http.expectOne((request) => request.url === 'http://localhost:3000/api/events').flush({ data: events });
    fixture.detectChanges();
  }

  function render(adminOrganizations: { id: number; name: string }[]): void {
    renderWithoutRecommendations(adminOrganizations);
    http.expectOne(recommendationsUrl).flush({ data: [] });
    fixture.detectChanges();
  }

  function recommendationsSection(): HTMLElement {
    return fixture.nativeElement.querySelector('section.recommendations');
  }

  function createLink(): HTMLAnchorElement | null {
    return fixture.nativeElement.querySelector('a[href="/events/new"]');
  }

  it('hides Create event from a user with no admin organizations', fakeAsync(() => {
    render([]);

    expect(createLink()).toBeNull();
  }));

  it('shows Create event to an organization admin', fakeAsync(() => {
    render([{ id: 1, name: 'Atlas' }]);

    expect(createLink()?.textContent?.trim()).toBe('Create event');
  }));

  it('shows recommendations in the order the server sent', fakeAsync(() => {
    renderWithoutRecommendations();
    http.expectOne(recommendationsUrl).flush({ data: [event(2, 'Second pick'), event(1, 'First pick')] });
    fixture.detectChanges();

    const titles = [...recommendationsSection().querySelectorAll('h3')].map((h) => h.textContent?.trim());
    expect(titles).toEqual(['Second pick', 'First pick']);
  }));

  it('says No recommendations yet when the list is empty', fakeAsync(() => {
    render([]);

    expect(recommendationsSection().textContent).toContain('No recommendations yet');
  }));

  it('shows a message when recommendations fail, and still lists events', fakeAsync(() => {
    renderWithoutRecommendations([], [event(5, 'Listed event')]);
    http.expectOne(recommendationsUrl).flush(
      { error: { code: 'recommendations_unavailable' } },
      { status: 503, statusText: 'Service Unavailable' },
    );
    fixture.detectChanges();

    expect(recommendationsSection().textContent).toContain('Recommendations not available currently, try again later');
    expect(fixture.nativeElement.textContent).toContain('Listed event');
  }));

  it('lists events without waiting for recommendations', fakeAsync(() => {
    renderWithoutRecommendations([], [event(5, 'Listed event')]);

    expect(fixture.nativeElement.textContent).toContain('Listed event');
    expect(recommendationsSection().textContent).toContain('Loading recommendations');
    http.expectOne(recommendationsUrl).flush({ data: [] });
  }));
});
