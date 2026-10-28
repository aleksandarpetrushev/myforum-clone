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

  function render(adminOrganizations: { id: number; name: string }[]): void {
    fixture = TestBed.createComponent(DiscoveryComponent);
    fixture.detectChanges();
    http.expectOne('http://localhost:3000/api/me/organizations').flush({ data: adminOrganizations });
    http.expectOne('http://localhost:3000/api/topics').flush({ data: [] });
    tick(200);
    http.expectOne((request) => request.url === 'http://localhost:3000/api/events').flush({ data: [] });
    fixture.detectChanges();
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
});
