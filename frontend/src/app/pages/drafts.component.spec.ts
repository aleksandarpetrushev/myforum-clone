import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { DraftsComponent } from './drafts.component';

describe('DraftsComponent', () => {
  let fixture: ComponentFixture<DraftsComponent>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [DraftsComponent],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();
    TestBed.inject(AuthService).token.set('test-token');
    http = TestBed.inject(HttpTestingController);
    fixture = TestBed.createComponent(DraftsComponent);
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  function draft(id: number, title: string, organization: string) {
    return { id, title, starts_at: '2026-11-20T09:00:00.000Z', ends_at: '2026-11-20T10:00:00.000Z', location: 'Geneva',
      kind: 'in_person', capacity: 10, reserved_spots: 0, status: 'draft', organization: { id: id, name: organization }, topics: [] };
  }

  it('lists each draft as not published, with its organization, in the order the server sent', () => {
    http.expectOne('http://localhost:3000/api/me/drafts').flush({ data: [draft(2, 'Embargoed panel', 'Borealis'), draft(1, 'Climate clinic', 'Atlas')] });
    fixture.detectChanges();

    const cards = [...fixture.nativeElement.querySelectorAll('article')] as HTMLElement[];
    expect(cards.map((card) => card.querySelector('h2')?.textContent?.trim())).toEqual(['Embargoed panel', 'Climate clinic']);
    expect(cards[0].textContent).toContain('Not published');
    expect(cards[0].textContent).toContain('Borealis');
    expect(cards[0].querySelector('a')?.getAttribute('href')).toBe('/events/2');
  });

  it('says No drafts when there are none', () => {
    http.expectOne('http://localhost:3000/api/me/drafts').flush({ data: [] });
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('No drafts');
  });
});
