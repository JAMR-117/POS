package inventory

import (
	"context"
	"errors"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetAlerts(ctx context.Context, tiendaID string, maxDays float64) ([]StockAlertItem, error) {
	if maxDays <= 0 {
		maxDays = 7.0 // Umbral base de 7 días de inventario proyectado
	}

	if tiendaID == "" {
		defaultID, err := s.repo.GetDefaultTiendaID(ctx)
		if err != nil {
			return nil, errors.New("TIENDA_NOT_CONFIGURED: ninguna tienda activa registrada")
		}
		tiendaID = defaultID
	}

	alerts, err := s.repo.GetStockAlerts(ctx, tiendaID, maxDays)
	if err != nil {
		return nil, err
	}

	if alerts == nil {
		return []StockAlertItem{}, nil
	}

	return alerts, nil
}

func (s *Service) GetVelocityCatalog(ctx context.Context, tiendaID, orderBy string, limit, offset int) ([]VelocityItem, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	if tiendaID == "" {
		defaultID, err := s.repo.GetDefaultTiendaID(ctx)
		if err != nil {
			return nil, errors.New("TIENDA_NOT_CONFIGURED: ninguna tienda activa registrada")
		}
		tiendaID = defaultID
	}

	items, err := s.repo.GetCatalogVelocity(ctx, tiendaID, orderBy, limit, offset)
	if err != nil {
		return nil, err
	}

	if items == nil {
		return []VelocityItem{}, nil
	}

	return items, nil
}
